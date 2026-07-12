#if canImport(UIKit) && canImport(AVFoundation) && canImport(Vision) && canImport(CoreImage)
import UIKit
import AVFoundation
import Vision
import CoreImage
import CoreGraphics

struct DepthMapOptions: Sendable {
    var quality: Int
    var invert: Bool
    var foregroundAssist: Bool
    var detail: Double
    var temporalSmoothing: Double
}

enum DepthMapError: Error, LocalizedError, Sendable {
    case noVideo
    case noDepthResult
    case readerFailed(String)
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideo:
            return "The selected file has no video track."
        case .noDepthResult:
            return "Vision could not estimate a usable relative-depth matte for this frame."
        case .readerFailed(let reason), .writerFailed(let reason):
            return reason
        }
    }
}

final class DepthMapExporter: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func previewPNGData(
        url: URL,
        time: Double,
        options: DepthMapOptions
    ) throws -> Data {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        var actual = CMTime.invalid
        let image = try generator.copyCGImage(
            at: CMTime(seconds: max(0, time), preferredTimescale: 600),
            actualTime: &actual
        )
        let input = CIImage(cgImage: image)
        let depth = try relativeDepth(for: input, options: options, previous: nil)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.pngRepresentation(
                of: depth,
                format: .RGBA8,
                colorSpace: colorSpace,
                options: [:]
              ) else {
            throw DepthMapError.noDepthResult
        }
        return data
    }

    func export(
        inputURL: URL,
        outputURL: URL,
        options: DepthMapOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let asset = AVURLAsset(url: inputURL)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw DepthMapError.noVideo
        }

        let naturalRect = CGRect(origin: .zero, size: track.naturalSize)
        let transformedRect = naturalRect.applying(track.preferredTransform).standardized
        let renderSize = CGSize(
            width: max(1, transformedRect.width.rounded()),
            height: max(1, transformedRect.height.rounded())
        )
        let translation = CGAffineTransform(
            translationX: -transformedRect.minX,
            y: -transformedRect.minY
        )

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw DepthMapError.readerFailed("Could not add the depth-map video reader output.")
        }
        reader.add(output)

        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let width = Int(renderSize.width)
        let height = Int(renderSize.height)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: max(2_000_000, width * height * 3),
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ],
            ]
        )
        writerInput.expectsMediaDataInRealTime = false
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
            throw DepthMapError.writerFailed("Could not add the depth-map writer input.")
        }
        writer.add(writerInput)

        guard reader.startReading() else {
            throw DepthMapError.readerFailed(reader.error?.localizedDescription ?? "Reader start failed.")
        }
        guard writer.startWriting() else {
            throw DepthMapError.writerFailed(writer.error?.localizedDescription ?? "Writer start failed.")
        }
        writer.startSession(atSourceTime: .zero)

        let duration = max(0.001, asset.duration.seconds)
        var previousDepth: CIImage?
        var processingError: Error?

        while processingError == nil, let sample = output.copyNextSampleBuffer() {
            autoreleasepool {
                guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample),
                      let pool = adaptor.pixelBufferPool else {
                    processingError = DepthMapError.readerFailed("A source frame could not be decoded.")
                    return
                }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                let source = CIImage(cvPixelBuffer: sourceBuffer)
                    .transformed(by: track.preferredTransform)
                    .transformed(by: translation)
                    .cropped(to: CGRect(origin: .zero, size: renderSize))
                do {
                    let depth = try relativeDepth(
                        for: source,
                        options: options,
                        previous: previousDepth
                    ).cropped(to: source.extent)
                    previousDepth = depth

                    var buffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                          let buffer else {
                        throw DepthMapError.writerFailed("Could not allocate a depth-map output buffer.")
                    }
                    context.render(
                        depth,
                        to: buffer,
                        bounds: source.extent,
                        colorSpace: CGColorSpaceCreateDeviceRGB()
                    )
                    while !writerInput.isReadyForMoreMediaData {
                        Thread.sleep(forTimeInterval: 0.002)
                    }
                    guard adaptor.append(buffer, withPresentationTime: pts) else {
                        throw DepthMapError.writerFailed(
                            writer.error?.localizedDescription ?? "Could not append a depth-map frame."
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
        semaphore.wait()
        guard writer.status == .completed else {
            throw DepthMapError.writerFailed(
                writer.error?.localizedDescription ?? "Depth-map export failed."
            )
        }
        progress(1)
    }

    private func relativeDepth(
        for input: CIImage,
        options: DepthMapOptions,
        previous: CIImage?
    ) throws -> CIImage {
        let extent = input.extent
        let saliency = try saliencyMask(for: input)
        var depth = intensity(saliency, weight: 0.78)

        let vertical = CIFilter(
            name: "CILinearGradient",
            parameters: [
                "inputPoint0": CIVector(x: extent.midX, y: extent.minY),
                "inputPoint1": CIVector(x: extent.midX, y: extent.maxY),
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                "inputColor1": CIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1),
            ]
        )?.outputImage?.cropped(to: extent)
            ?? CIImage(color: .black).cropped(to: extent)
        depth = add(depth, intensity(vertical, weight: 0.22), extent: extent)

        if options.foregroundAssist,
           let person = try? personMask(for: input, quality: options.quality) {
            depth = maximum(depth, intensity(person, weight: 0.96), extent: extent)
        }

        let contrast = 0.7 + min(max(options.detail, 0), 1) * 1.9
        depth = depth.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0,
            kCIInputContrastKey: contrast,
            kCIInputBrightnessKey: 0,
        ])

        let radius = 1.0 + (1 - min(max(options.detail, 0), 1)) * 8.0
        depth = depth.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)

        let smoothing = min(max(options.temporalSmoothing, 0), 0.92)
        if smoothing > 0, let previous {
            let currentPart = intensity(depth, weight: 1 - smoothing)
            let previousPart = intensity(previous, weight: smoothing)
            depth = add(currentPart, previousPart, extent: extent)
        }

        depth = depth.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ]).cropped(to: extent)

        if options.invert {
            depth = depth.applyingFilter("CIColorInvert").cropped(to: extent)
        }
        return depth
    }

    private func saliencyMask(for image: CIImage) throws -> CIImage {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first as? VNSaliencyImageObservation else {
            throw DepthMapError.noDepthResult
        }
        return scaledMask(CIImage(cvPixelBuffer: observation.pixelBuffer), to: image.extent)
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
            throw DepthMapError.noDepthResult
        }
        return scaledMask(CIImage(cvPixelBuffer: observation.pixelBuffer), to: image.extent)
    }

    private func scaledMask(_ mask: CIImage, to extent: CGRect) -> CIImage {
        let sx = extent.width / max(1, mask.extent.width)
        let sy = extent.height / max(1, mask.extent.height)
        return mask
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
    }

    private func intensity(_ image: CIImage, weight: Double) -> CIImage {
        let w = CGFloat(weight)
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: w, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: w, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: w, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
    }

    private func add(_ foreground: CIImage, _ background: CIImage, extent: CGRect) -> CIImage {
        foreground.applyingFilter("CIAdditionCompositing", parameters: [
            kCIInputBackgroundImageKey: background,
        ]).cropped(to: extent)
    }

    private func maximum(_ foreground: CIImage, _ background: CIImage, extent: CGRect) -> CIImage {
        foreground.applyingFilter("CIMaximumCompositing", parameters: [
            kCIInputBackgroundImageKey: background,
        ]).cropped(to: extent)
    }
}

@MainActor
final class DepthMapStudioViewController: UIViewController {
    private let preview = VideoPreviewPanel()
    private let depthPreview = UIImageView()
    private let sourceLabel = ExtensionUI.label("No source video selected.")
    private let quality = UISegmentedControl(items: ["Fast", "Balanced", "Accurate"])
    private let invertSwitch = UISwitch()
    private let foregroundSwitch = UISwitch()
    private let detailSlider = UISlider()
    private let smoothingSlider = UISlider()
    private let progress = UIProgressView(progressViewStyle: .default)
    private let status = ExtensionUI.label("Relative depth uses on-device Vision saliency and foreground cues.")
    private var sourceURL: URL?
    private var picker: MediaSourcePicker?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Depth Map Studio"
        view.backgroundColor = .systemBackground
        quality.selectedSegmentIndex = 1
        foregroundSwitch.isOn = true
        invertSwitch.isOn = false
        detailSlider.minimumValue = 0
        detailSlider.maximumValue = 1
        detailSlider.value = 0.65
        smoothingSlider.minimumValue = 0
        smoothingSlider.maximumValue = 0.9
        smoothingSlider.value = 0.45

        depthPreview.translatesAutoresizingMaskIntoConstraints = false
        depthPreview.contentMode = .scaleAspectFit
        depthPreview.backgroundColor = .black
        depthPreview.layer.cornerRadius = 12
        depthPreview.layer.masksToBounds = true
        depthPreview.heightAnchor.constraint(equalToConstant: 240).isActive = true

        let photos = ExtensionUI.button("Choose from Photos", action: UIAction { [weak self] _ in self?.choose(photos: true) })
        let files = ExtensionUI.secondaryButton("Choose from Files", action: UIAction { [weak self] _ in self?.choose(photos: false) })
        let pickerRow = ExtensionUI.horizontalStack([photos, files])
        let previewButton = ExtensionUI.button("Preview Depth at Playhead", action: UIAction { [weak self] _ in self?.previewDepth() })
        let export = ExtensionUI.secondaryButton("Export Depth Map", action: UIAction { [weak self] action in
            self?.render(returnToTimeline: false, source: action.sender as? UIView)
        })
        let timeline = ExtensionUI.button("Render & Return to Timeline", action: UIAction { [weak self] action in
            self?.render(returnToTimeline: true, source: action.sender as? UIView)
        })

        let stack = ExtensionUI.stack([
            ExtensionUI.label("Generates a grayscale relative-depth video automatically. White represents near regions by default. This is a lightweight system-only estimate, not a metric camera depth scan."),
            preview,
            pickerRow,
            sourceLabel,
            quality,
            ExtensionUI.labeledSwitch("Foreground/person assist", control: foregroundSwitch),
            ExtensionUI.labeledSwitch("Invert near/far", control: invertSwitch),
            ExtensionUI.label("Detail", style: .footnote),
            detailSlider,
            ExtensionUI.label("Temporal smoothing", style: .footnote),
            smoothingSlider,
            previewButton,
            depthPreview,
            progress,
            ExtensionUI.horizontalStack([export, timeline]),
            status,
            ExtensionUI.label("Render & Return to Timeline saves the map as the newest Photos video and safely returns to the project. Tap Add Layer once to choose the newest video.", style: .footnote),
        ])
        _ = ExtensionUI.installScrollStack(stack, in: self)
    }

    private func choose(photos: Bool) {
        let picker = MediaSourcePicker(presenter: self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                self.sourceURL = url
                self.preview.load(url: url)
                self.sourceLabel.text = url.lastPathComponent
                self.status.text = "Ready. Preview a frame or render the complete depth map."
            case .failure(let error):
                ExtensionUI.alert(title: "Import failed", message: error.localizedDescription, from: self)
            }
        }
        self.picker = picker
        photos ? picker.presentPhotos() : picker.presentFiles()
    }

    private func currentOptions() -> DepthMapOptions {
        DepthMapOptions(
            quality: quality.selectedSegmentIndex,
            invert: invertSwitch.isOn,
            foregroundAssist: foregroundSwitch.isOn,
            detail: Double(detailSlider.value),
            temporalSmoothing: Double(smoothingSlider.value)
        )
    }

    private func previewDepth() {
        guard let sourceURL else {
            ExtensionUI.alert(title: "Choose a video", message: "Select a source video first.", from: self)
            return
        }
        let time = preview.currentTime
        let options = currentOptions()
        status.text = "Estimating relative depth…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try DepthMapExporter().previewPNGData(url: sourceURL, time: time, options: options)
                }.value
                self.depthPreview.image = UIImage(data: data)
                self.status.text = "Depth preview complete."
            } catch {
                self.status.text = "Depth preview failed."
                ExtensionUI.alert(title: "Depth preview failed", message: error.localizedDescription, from: self)
            }
        }
    }

    private func render(returnToTimeline: Bool, source: UIView?) {
        guard let sourceURL else {
            ExtensionUI.alert(title: "Choose a video", message: "Select a source video first.", from: self)
            return
        }
        let options = currentOptions()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("AE-Motion-Depth-\(UUID().uuidString).mov")
        progress.progress = 0
        status.text = "Rendering relative depth map…"

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try DepthMapExporter().export(
                        inputURL: sourceURL,
                        outputURL: output,
                        options: options
                    ) { value in
                        Task { @MainActor [weak self] in
                            self?.progress.progress = Float(value)
                        }
                    }
                }.value
                if returnToTimeline {
                    self.status.text = "Rendered. Saving and returning to timeline…"
                    TimelineHandoffCoordinator.renderResultReady(fileURL: output, from: self) { [weak self] result in
                        guard let self else { return }
                        switch result {
                        case .success:
                            self.status.text = "Depth map saved as the newest Photos video."
                        case .failure(let error):
                            self.status.text = "Depth map rendered, but timeline return was incomplete."
                            ExtensionUI.alert(title: "Depth map handoff", message: error.localizedDescription, from: self)
                        }
                    }
                } else {
                    self.status.text = "Depth-map export complete."
                    ExtensionUI.share(fileURL: output, from: self, source: source)
                }
            } catch {
                self.status.text = "Depth-map render failed."
                ExtensionUI.alert(title: "Depth-map render failed", message: error.localizedDescription, from: self)
            }
        }
    }
}
#endif
