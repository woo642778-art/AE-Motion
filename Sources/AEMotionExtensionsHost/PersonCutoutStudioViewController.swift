#if canImport(UIKit) && canImport(AVFoundation) && canImport(Vision) && canImport(CoreImage)
import UIKit
import AVFoundation
import Vision
import CoreImage
import CoreGraphics
import ImageIO
import AEMotionExtensionsCore

struct PersonCutoutOptions: Sendable {
    var quality: Int
    var outputAlpha: Bool
    var manualMask: ManualMaskDefinition
    var trackingPath: CutoutTrackingPath?
}

enum PersonCutoutError: Error, LocalizedError, Sendable {
    case noVideo
    case noResult
    case writerFailed(String)
    case readerFailed(String)
    case unsupportedAlpha
    case maskRasterizationFailed

    var errorDescription: String? {
        switch self {
        case .noVideo: return "The selected file has no video track."
        case .noResult: return "Vision did not return a person mask."
        case .writerFailed(let reason): return reason
        case .readerFailed(let reason): return reason
        case .unsupportedAlpha: return "This device could not create an HEVC-with-alpha output."
        case .maskRasterizationFailed: return "The manual cutout mask could not be rasterized."
        }
    }
}

private enum ManualMaskRasterizer {
    static func maskImage(
        definition: ManualMaskDefinition,
        size: CGSize,
        keep: Bool
    ) throws -> CIImage? {
        let operations = definition.operations.filter { operation in
            if keep {
                return operation.kind == .keepStroke || operation.kind == .keepRectangle
            }
            return operation.kind == .removeStroke
        }
        guard !operations.isEmpty else { return nil }

        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        var storage = [UInt8](repeating: 0, count: width * height)
        var image: CGImage?

        storage.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return }

            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.setStrokeColor(gray: 1, alpha: 1)
            context.setFillColor(gray: 1, alpha: 1)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            func point(_ normalized: NormalizedMaskPoint) -> CGPoint {
                CGPoint(
                    x: CGFloat(normalized.x) * CGFloat(width),
                    y: CGFloat(normalized.y) * CGFloat(height)
                )
            }

            for operation in operations {
                switch operation.kind {
                case .keepStroke, .removeStroke:
                    guard let first = operation.points.first else { continue }
                    let lineWidth = CGFloat(max(0.005, operation.radius)) * CGFloat(min(width, height)) * 2
                    context.setLineWidth(lineWidth)
                    if operation.points.count == 1 {
                        let center = point(first)
                        context.fillEllipse(in: CGRect(
                            x: center.x - lineWidth * 0.5,
                            y: center.y - lineWidth * 0.5,
                            width: lineWidth,
                            height: lineWidth
                        ))
                    } else {
                        context.beginPath()
                        context.move(to: point(first))
                        for value in operation.points.dropFirst() {
                            context.addLine(to: point(value))
                        }
                        context.strokePath()
                    }
                case .keepRectangle:
                    guard operation.points.count >= 2 else { continue }
                    let a = point(operation.points[0])
                    let b = point(operation.points[1])
                    context.fill(CGRect(
                        x: min(a.x, b.x),
                        y: min(a.y, b.y),
                        width: abs(a.x - b.x),
                        height: abs(a.y - b.y)
                    ))
                }
            }
            image = context.makeImage()
        }

        guard let image else { throw PersonCutoutError.maskRasterizationFailed }
        return CIImage(cgImage: image).cropped(to: CGRect(origin: .zero, size: size))
    }
}

final class PersonCutoutExporter: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func sourceFramePNGData(url: URL, time: Double) throws -> Data {
        let input = try sourceFrame(url: url, time: time)
        return try pngData(for: input, extent: input.extent)
    }

    func previewPNGData(
        url: URL,
        time: Double,
        quality: Int,
        manualMask: ManualMaskDefinition,
        trackingPath: CutoutTrackingPath? = nil
    ) throws -> Data {
        let input = try sourceFrame(url: url, time: time)
        let frameMask = trackedMaskDefinition(
            manualMask,
            trackingPath: trackingPath,
            time: time
        )
        let finalMask = try combinedMask(
            for: input,
            quality: quality,
            manualMask: frameMask
        )
        let transparent = CIImage(color: .clear).cropped(to: input.extent)
        let output = input.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: transparent,
            kCIInputMaskImageKey: finalMask,
        ])
        return try pngData(for: output, extent: input.extent)
    }

    func export(
        inputURL: URL,
        outputURL: URL,
        options: PersonCutoutOptions,
        cancellationToken: RenderCancellationToken? = nil,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        try cancellationToken?.checkCancellation()
        let asset = AVURLAsset(url: inputURL)
        guard let sourceTrack = asset.tracks(withMediaType: .video).first else {
            throw PersonCutoutError.noVideo
        }

        let naturalRect = CGRect(origin: .zero, size: sourceTrack.naturalSize)
        let transformedRect = naturalRect.applying(sourceTrack.preferredTransform).standardized
        let sourceRenderSize = CGSize(
            width: max(1, transformedRect.width.rounded()),
            height: max(1, transformedRect.height.rounded())
        )
        let dimensions = RenderSizePolicy.constrained(
            width: Int(sourceRenderSize.width),
            height: Int(sourceRenderSize.height)
        )
        let renderSize = CGSize(width: dimensions.width, height: dimensions.height)
        let outputScale = CGAffineTransform(
            scaleX: renderSize.width / max(1, sourceRenderSize.width),
            y: renderSize.height / max(1, sourceRenderSize.height)
        )
        let translation = CGAffineTransform(
            translationX: -transformedRect.minX,
            y: -transformedRect.minY
        )

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: sourceTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw PersonCutoutError.readerFailed("Could not add the video reader output.")
        }
        reader.add(readerOutput)

        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let width = Int(renderSize.width)
        let height = Int(renderSize.height)
        let codec: AVVideoCodecType = options.outputAlpha ? .hevcWithAlpha : .hevc
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: codec,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        writerInput.expectsMediaDataInRealTime = false
        writerInput.transform = .identity
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )
        guard writer.canAdd(writerInput) else {
            throw options.outputAlpha
                ? PersonCutoutError.unsupportedAlpha
                : PersonCutoutError.writerFailed("Could not add the cutout video writer input.")
        }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw PersonCutoutError.readerFailed(reader.error?.localizedDescription ?? "Reader start failed.")
        }
        guard writer.startWriting() else {
            throw PersonCutoutError.writerFailed(writer.error?.localizedDescription ?? "Writer start failed.")
        }
        writer.startSession(atSourceTime: .zero)

        let duration = max(0.001, asset.duration.seconds)
        var processingError: Error?
        while processingError == nil, let sample = readerOutput.copyNextSampleBuffer() {
            do {
                try cancellationToken?.checkCancellation()
            } catch {
                processingError = error
                break
            }
            autoreleasepool {
                guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample),
                      let pool = adaptor.pixelBufferPool else {
                    processingError = PersonCutoutError.readerFailed("A source frame could not be decoded.")
                    return
                }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                let rawInput = CIImage(cvPixelBuffer: sourceBuffer)
                let input = rawInput
                    .transformed(by: sourceTrack.preferredTransform)
                    .transformed(by: translation)
                    .cropped(to: CGRect(origin: .zero, size: sourceRenderSize))
                    .transformed(by: outputScale)
                    .cropped(to: CGRect(origin: .zero, size: renderSize))
                do {
                    let frameMask = trackedMaskDefinition(
                        options.manualMask,
                        trackingPath: options.trackingPath,
                        time: pts.seconds
                    )
                    let mask = try combinedMask(
                        for: input,
                        quality: options.quality,
                        manualMask: frameMask
                    )
                    let background: CIImage
                    if options.outputAlpha {
                        background = CIImage(color: .clear).cropped(to: input.extent)
                    } else {
                        background = CIImage(
                            color: CIColor(red: 0, green: 1, blue: 0, alpha: 1)
                        ).cropped(to: input.extent)
                    }
                    let composited = input.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: background,
                        kCIInputMaskImageKey: mask,
                    ])
                    var outputBuffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer) == kCVReturnSuccess,
                          let outputBuffer else {
                        throw PersonCutoutError.writerFailed("Could not allocate an output pixel buffer.")
                    }
                    context.render(
                        composited,
                        to: outputBuffer,
                        bounds: input.extent,
                        colorSpace: CGColorSpaceCreateDeviceRGB()
                    )
                    while !writerInput.isReadyForMoreMediaData {
                        try cancellationToken?.checkCancellation()
                        Thread.sleep(forTimeInterval: 0.002)
                    }
                    guard adaptor.append(outputBuffer, withPresentationTime: pts) else {
                        throw PersonCutoutError.writerFailed(
                            writer.error?.localizedDescription ?? "Could not append a cutout frame."
                        )
                    }
                    progress(min(1, max(0, pts.seconds / duration)))
                } catch {
                    processingError = error
                }
            }
        }

        if let processingError {
            reader.cancelReading()
            writer.cancelWriting()
            throw processingError
        }

        writerInput.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
            do {
                try cancellationToken?.checkCancellation()
            } catch {
                writer.cancelWriting()
                throw error
            }
        }
        guard writer.status == .completed else {
            throw PersonCutoutError.writerFailed(
                writer.error?.localizedDescription ?? "Cutout export failed."
            )
        }
    }

    private func sourceFrame(url: URL, time: Double) throws -> CIImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        var actual = CMTime.invalid
        let image = try generator.copyCGImage(
            at: CMTime(seconds: max(0, time), preferredTimescale: 600),
            actualTime: &actual
        )
        return CIImage(cgImage: image)
    }

    private func trackedMaskDefinition(
        _ definition: ManualMaskDefinition,
        trackingPath: CutoutTrackingPath?,
        time: Double
    ) -> ManualMaskDefinition {
        guard let trackingPath else { return definition }
        return definition.transformed(
            from: trackingPath.anchorRect,
            to: trackingPath.rect(at: time)
        )
    }

    private func combinedMask(
        for input: CIImage,
        quality: Int,
        manualMask: ManualMaskDefinition
    ) throws -> CIImage {
        let vision = try personMask(for: input, quality: quality)
        var result = vision.transformed(by: CGAffineTransform(
            scaleX: input.extent.width / max(1, vision.extent.width),
            y: input.extent.height / max(1, vision.extent.height)
        )).cropped(to: input.extent)

        if let keep = try ManualMaskRasterizer.maskImage(
            definition: manualMask,
            size: input.extent.size,
            keep: true
        ) {
            result = result.applyingFilter("CIMaximumCompositing", parameters: [
                kCIInputBackgroundImageKey: keep,
            ]).cropped(to: input.extent)
        }

        if let remove = try ManualMaskRasterizer.maskImage(
            definition: manualMask,
            size: input.extent.size,
            keep: false
        ) {
            let inverse = remove.applyingFilter("CIColorInvert").cropped(to: input.extent)
            result = result.applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: inverse,
            ]).cropped(to: input.extent)
        }
        return result
    }

    private func personMask(for image: CIImage, quality: Int) throws -> CIImage {
        let request = VNGeneratePersonSegmentationRequest()
        switch quality {
        case 0: request.qualityLevel = .fast
        case 2: request.qualityLevel = .accurate
        default: request.qualityLevel = .balanced
        }
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first as? VNPixelBufferObservation else {
            throw PersonCutoutError.noResult
        }
        return CIImage(cvPixelBuffer: observation.pixelBuffer)
    }

    private func pngData(for image: CIImage, extent: CGRect) throws -> Data {
        guard let cg = context.createCGImage(image, from: extent) else {
            throw PersonCutoutError.noResult
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw PersonCutoutError.noResult
        }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PersonCutoutError.noResult
        }
        return data as Data
    }
}

@MainActor
final class PersonCutoutStudioViewController: UIViewController {
    private let preview = VideoPreviewPanel()
    private let maskEditor = ManualMaskEditorView()
    private let cutoutPreview = UIImageView()
    private let sourceLabel = ExtensionUI.label("No source video selected.")
    private let quality = UISegmentedControl(items: ["Fast", "Balanced", "Accurate"])
    private let editMode = UISegmentedControl(items: ["Keep Brush", "Erase Brush", "Box Select"])
    private let brushSlider = UISlider()
    private let trackingQuality = UISegmentedControl(items: ["Fast", "Accurate"])
    private let trackingFPS = UISegmentedControl(items: ["12 fps", "24 fps", "30 fps"])
    private let alphaSwitch = UISwitch()
    private let progress = UIProgressView(progressViewStyle: .default)
    private let status = ExtensionUI.label("Person segmentation uses the on-device Vision pipeline.")
    private let exportButton = ExtensionUI.secondaryButton("Export Cutout", action: UIAction { _ in })
    private let timelineButton = ExtensionUI.button("Render & Return to Timeline", action: UIAction { _ in })
    private let cancelRenderButton = ExtensionUI.secondaryButton("Cancel Render", action: UIAction { _ in })
    private weak var pageScrollView: UIScrollView?
    private lazy var renderJob = RenderJobCoordinator(owner: self, progressView: progress, statusLabel: status)
    private var picker: MediaSourcePicker?
    private var sourceURL: URL?
    private var trackingPath: CutoutTrackingPath?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Person Cutout Studio"
        view.backgroundColor = .systemBackground
        quality.selectedSegmentIndex = 1
        editMode.selectedSegmentIndex = 0
        trackingQuality.selectedSegmentIndex = 1
        trackingFPS.selectedSegmentIndex = 1
        alphaSwitch.isOn = true

        brushSlider.minimumValue = 0.01
        brushSlider.maximumValue = 0.16
        brushSlider.value = 0.045
        brushSlider.addAction(UIAction { [weak self] action in
            guard let self, let slider = action.sender as? UISlider else { return }
            self.maskEditor.brushRadius = Double(slider.value)
        }, for: .valueChanged)

        editMode.addAction(UIAction { [weak self] action in
            guard let self, let control = action.sender as? UISegmentedControl,
                  let mode = ManualMaskEditorView.Mode(rawValue: control.selectedSegmentIndex) else { return }
            self.maskEditor.mode = mode
        }, for: .valueChanged)

        maskEditor.heightAnchor.constraint(equalToConstant: 300).isActive = true
        maskEditor.onMaskChange = { [weak self] definition in
            guard let self else { return }
            self.trackingPath = nil
            self.status.text = definition.isEmpty
                ? "Manual mask cleared. Vision segmentation only."
                : "Manual mask updated. Auto Track must be analyzed again."
        }
        maskEditor.onInteractionChanged = { [weak self] interacting in
            self?.setPageScrollingEnabled(!interacting)
        }

        cutoutPreview.translatesAutoresizingMaskIntoConstraints = false
        cutoutPreview.contentMode = .scaleAspectFit
        cutoutPreview.backgroundColor = .tertiarySystemBackground
        cutoutPreview.layer.cornerRadius = 12
        cutoutPreview.layer.masksToBounds = true
        cutoutPreview.heightAnchor.constraint(equalToConstant: 220).isActive = true

        let photos = ExtensionUI.button("Choose from Photos", action: UIAction { [weak self] _ in self?.choose(photos: true) })
        let files = ExtensionUI.secondaryButton("Choose from Files", action: UIAction { [weak self] _ in self?.choose(photos: false) })
        let pickerRow = ExtensionUI.horizontalStack([photos, files])
        let loadFrame = ExtensionUI.secondaryButton("Load Frame at Playhead", action: UIAction { [weak self] _ in self?.loadFrameAtPlayhead() })
        let previewButton = ExtensionUI.button("Preview Composite", action: UIAction { [weak self] _ in self?.previewCurrentFrame() })
        let analyzeTrack = ExtensionUI.button("Auto Track Selection", action: UIAction { [weak self] _ in self?.analyzeTracking() })
        let undo = ExtensionUI.secondaryButton("Undo Mask", action: UIAction { [weak self] _ in self?.maskEditor.undo() })
        let clear = ExtensionUI.secondaryButton("Clear Mask", action: UIAction { [weak self] _ in self?.maskEditor.clear() })
        let maskActions = ExtensionUI.horizontalStack([undo, clear])
        exportButton.addAction(UIAction { [weak self] action in
            self?.render(addToTimeline: false, source: action.sender as? UIView)
        }, for: .touchUpInside)
        timelineButton.addAction(UIAction { [weak self] action in
            self?.render(addToTimeline: true, source: action.sender as? UIView)
        }, for: .touchUpInside)
        cancelRenderButton.isEnabled = false
        cancelRenderButton.addAction(UIAction { [weak self] _ in self?.renderJob.cancel() }, for: .touchUpInside)
        let renderActions = ExtensionUI.horizontalStack([exportButton, timelineButton])
        let alphaRow = ExtensionUI.labeledSwitch("Transparent HEVC alpha", control: alphaSwitch)

        let stack = ExtensionUI.stack([
            ExtensionUI.label("Load an anchor frame, paint or box-select the subject, then run Auto Track Selection. Vision re-segments every frame while the manual correction follows the tracked position and scale."),
            preview,
            pickerRow,
            sourceLabel,
            quality,
            loadFrame,
            editMode,
            ExtensionUI.label("Brush size", style: .footnote),
            brushSlider,
            maskEditor,
            maskActions,
            ExtensionUI.label("Tracking quality", style: .footnote),
            trackingQuality,
            ExtensionUI.label("Tracking sample rate", style: .footnote),
            trackingFPS,
            analyzeTrack,
            previewButton,
            cutoutPreview,
            alphaRow,
            progress,
            renderActions,
            cancelRenderButton,
            status,
            ExtensionUI.label("Render & Return to Timeline saves the result as the newest Photos video and safely returns to the project. The unsafe private Add Layer call was removed because it caused a completion-time crash.", style: .footnote),
        ])
        pageScrollView = ExtensionUI.installScrollStack(stack, in: self)
    }

    private func choose(photos: Bool) {
        let picker = MediaSourcePicker(presenter: self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                self.sourceURL = url
                self.trackingPath = nil
                self.preview.load(url: url)
                self.sourceLabel.text = url.lastPathComponent
                self.status.text = "Ready. Load a frame at the playhead and edit its mask."
                self.loadFrameAtPlayhead()
            case .failure(let error):
                ExtensionUI.alert(title: "Import failed", message: error.localizedDescription, from: self)
            }
        }
        self.picker = picker
        photos ? picker.presentPhotos() : picker.presentFiles()
    }

    private func loadFrameAtPlayhead() {
        guard let sourceURL else {
            ExtensionUI.alert(title: "Choose a video", message: "Select a source video first.", from: self)
            return
        }
        let time = preview.currentTime
        status.text = "Loading source frame…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try PersonCutoutExporter().sourceFramePNGData(url: sourceURL, time: time)
                }.value
                self.maskEditor.setImage(UIImage(data: data))
                self.status.text = "Frame loaded. Paint or box-select the mask, then preview."
            } catch {
                self.status.text = "Frame load failed."
                ExtensionUI.alert(title: "Frame load failed", message: error.localizedDescription, from: self)
            }
        }
    }

    private func previewCurrentFrame() {
        guard let sourceURL else {
            ExtensionUI.alert(title: "Choose a video", message: "Select a source video first.", from: self)
            return
        }
        let time = preview.currentTime
        let qualityValue = quality.selectedSegmentIndex
        let manualMask = maskEditor.definition()
        let activeTrackingPath = trackingPath
        status.text = "Generating cutout preview…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try PersonCutoutExporter().previewPNGData(
                        url: sourceURL,
                        time: time,
                        quality: qualityValue,
                        manualMask: manualMask,
                        trackingPath: activeTrackingPath
                    )
                }.value
                self.cutoutPreview.image = UIImage(data: data)
                self.status.text = "Preview complete."
            } catch {
                self.status.text = "Preview failed."
                ExtensionUI.alert(title: "Cutout failed", message: error.localizedDescription, from: self)
            }
        }
    }

    private func analyzeTracking() {
        guard let sourceURL else {
            ExtensionUI.alert(title: "Choose a video", message: "Select a source video first.", from: self)
            return
        }
        guard let seedRect = maskEditor.definition().trackingSeedRect() else {
            ExtensionUI.alert(
                title: "Create a tracking selection",
                message: "Use Keep Brush or Box Select around the subject on the anchor frame first.",
                from: self
            )
            return
        }
        let fpsValues = [12.0, 24.0, 30.0]
        let fpsIndex = min(max(trackingFPS.selectedSegmentIndex, 0), fpsValues.count - 1)
        let fps = fpsValues[fpsIndex]
        let anchor = preview.currentTime
        let accurate = trackingQuality.selectedSegmentIndex == 1
        progress.progress = 0
        status.text = "Tracking the selection forward and backward…"

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let path = try await Task.detached(priority: .userInitiated) {
                    try CutoutTrackingEngine().track(
                        inputURL: sourceURL,
                        anchorTime: anchor,
                        seedRect: seedRect,
                        samplesPerSecond: fps,
                        accurate: accurate
                    ) { value in
                        Task { @MainActor [weak self] in
                            self?.progress.progress = Float(value)
                        }
                    }
                }.value
                self.trackingPath = path
                self.status.text = "Auto Track ready: \(path.samples.count) tracked samples. Preview or render."
            } catch {
                self.trackingPath = nil
                self.status.text = "Auto Track failed. Refine the selection and try again."
                ExtensionUI.alert(title: "Tracking failed", message: error.localizedDescription, from: self)
            }
        }
    }

    private func render(addToTimeline: Bool, source: UIView?) {
        guard let sourceURL else {
            ExtensionUI.alert(title: "Choose a video", message: "Select a source video first.", from: self)
            return
        }
        let options = PersonCutoutOptions(
            quality: quality.selectedSegmentIndex,
            outputAlpha: alphaSwitch.isOn,
            manualMask: maskEditor.definition(),
            trackingPath: trackingPath
        )
        let output = RenderTemporaryFiles.makeURL(label: "Cutout")
        let controls: [UIControl] = [
            quality, editMode, brushSlider, trackingQuality, trackingFPS, alphaSwitch, exportButton, timelineButton
        ]

        renderJob.start(
            name: "Person Cutout",
            outputURL: output,
            controls: controls,
            cancelButton: cancelRenderButton,
            initialStatus: addToTimeline ? "Rendering for timeline handoff…" : "Exporting cutout video…",
            operation: { token, progress in
                try PersonCutoutExporter().export(
                    inputURL: sourceURL,
                    outputURL: output,
                    options: options,
                    cancellationToken: token,
                    progress: progress
                )
            },
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    if addToTimeline {
                        self.status.text = "Rendered. Saving and returning to timeline…"
                        TimelineHandoffCoordinator.renderResultReady(fileURL: output, from: self) { [weak self] handoff in
                            guard let self else { return }
                            switch handoff {
                            case .success:
                                self.renderJob.outputWasConsumed(output)
                                self.status.text = "Saved as the newest Photos clip and returning to the timeline."
                            case .failure(let error):
                                self.status.text = "Rendered, but the safe timeline return was incomplete."
                                ExtensionUI.alert(title: "Timeline handoff", message: error.localizedDescription, from: self)
                            }
                        }
                    } else {
                        self.status.text = options.outputAlpha
                            ? "Transparent cutout export complete."
                            : "Green-background cutout export complete."
                        ExtensionUI.share(fileURL: output, from: self, source: source)
                    }
                case .failure(.cancelled):
                    self.status.text = "Cutout render cancelled."
                case .failure(let error):
                    self.status.text = "Render failed: \(error.localizedDescription)"
                    ExtensionUI.alert(title: "Cutout render failed", message: error.localizedDescription, from: self)
                }
            }
        )
    }

    private func setPageScrollingEnabled(_ enabled: Bool) {
        pageScrollView?.panGestureRecognizer.isEnabled = enabled
        pageScrollView?.isDirectionalLockEnabled = !enabled
    }
}
#endif
