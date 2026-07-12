#if canImport(UIKit) && canImport(AVFoundation) && canImport(Vision) && canImport(CoreImage)
import UIKit
import AVFoundation
import Vision
import CoreImage
import ImageIO

struct PersonCutoutOptions: Sendable {
    var quality: Int
    var outputAlpha: Bool
}

enum PersonCutoutError: Error, LocalizedError, Sendable {
    case noVideo
    case noResult
    case writerFailed(String)
    case readerFailed(String)
    case unsupportedAlpha

    var errorDescription: String? {
        switch self {
        case .noVideo: return "The selected file has no video track."
        case .noResult: return "Vision did not return a person mask."
        case .writerFailed(let reason): return reason
        case .readerFailed(let reason): return reason
        case .unsupportedAlpha: return "This device could not create an HEVC-with-alpha output."
        }
    }
}

final class PersonCutoutExporter: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func previewPNGData(url: URL, time: Double, quality: Int) throws -> Data {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        var actual = CMTime.invalid
        let image = try generator.copyCGImage(
            at: CMTime(seconds: max(0, time), preferredTimescale: 600),
            actualTime: &actual
        )
        let input = CIImage(cgImage: image)
        let mask = try personMask(for: input, quality: quality)
        let scaledMask = mask.transformed(by: CGAffineTransform(
            scaleX: input.extent.width / max(1, mask.extent.width),
            y: input.extent.height / max(1, mask.extent.height)
        ))
        let transparent = CIImage(color: .clear).cropped(to: input.extent)
        let output = input.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: transparent,
            kCIInputMaskImageKey: scaledMask,
        ])
        guard let cg = context.createCGImage(output, from: input.extent) else {
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

    func export(
        inputURL: URL,
        outputURL: URL,
        options: PersonCutoutOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let asset = AVURLAsset(url: inputURL)
        guard let sourceTrack = asset.tracks(withMediaType: .video).first else {
            throw PersonCutoutError.noVideo
        }
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
        let width = Int(sourceTrack.naturalSize.width.rounded())
        let height = Int(sourceTrack.naturalSize.height.rounded())
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
        writerInput.transform = sourceTrack.preferredTransform
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
            throw options.outputAlpha ? PersonCutoutError.unsupportedAlpha : PersonCutoutError.writerFailed("Could not add the cutout video writer input.")
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
        while let sample = readerOutput.copyNextSampleBuffer() {
            autoreleasepool {
                guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample),
                      let pool = adaptor.pixelBufferPool else { return }
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                let input = CIImage(cvPixelBuffer: sourceBuffer)
                do {
                    let mask = try personMask(for: input, quality: options.quality)
                    let scaledMask = mask.transformed(by: CGAffineTransform(
                        scaleX: input.extent.width / max(1, mask.extent.width),
                        y: input.extent.height / max(1, mask.extent.height)
                    ))
                    let background: CIImage
                    if options.outputAlpha {
                        background = CIImage(color: .clear).cropped(to: input.extent)
                    } else {
                        background = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 1)).cropped(to: input.extent)
                    }
                    let composited = input.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: background,
                        kCIInputMaskImageKey: scaledMask,
                    ])
                    var outputBuffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer) == kCVReturnSuccess,
                          let outputBuffer else { return }
                    context.render(composited, to: outputBuffer, bounds: input.extent, colorSpace: CGColorSpaceCreateDeviceRGB())
                    while !writerInput.isReadyForMoreMediaData {
                        Thread.sleep(forTimeInterval: 0.002)
                    }
                    guard adaptor.append(outputBuffer, withPresentationTime: pts) else { return }
                    progress(min(1, max(0, pts.seconds / duration)))
                } catch {
                    return
                }
            }
        }

        writerInput.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        guard writer.status == .completed else {
            throw PersonCutoutError.writerFailed(writer.error?.localizedDescription ?? "Cutout export failed.")
        }
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
}

@MainActor
final class PersonCutoutStudioViewController: UIViewController {
    private let preview = VideoPreviewPanel()
    private let cutoutPreview = UIImageView()
    private let sourceLabel = ExtensionUI.label("No source video selected.")
    private let quality = UISegmentedControl(items: ["Fast", "Balanced", "Accurate"])
    private let alphaSwitch = UISwitch()
    private let progress = UIProgressView(progressViewStyle: .default)
    private let status = ExtensionUI.label("Person segmentation uses the on-device Vision pipeline.")
    private var picker: MediaSourcePicker?
    private var sourceURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Person Cutout Studio"
        view.backgroundColor = .systemBackground
        quality.selectedSegmentIndex = 1
        alphaSwitch.isOn = true

        cutoutPreview.translatesAutoresizingMaskIntoConstraints = false
        cutoutPreview.contentMode = .scaleAspectFit
        cutoutPreview.backgroundColor = .tertiarySystemBackground
        cutoutPreview.layer.cornerRadius = 12
        cutoutPreview.layer.masksToBounds = true
        cutoutPreview.heightAnchor.constraint(equalToConstant: 220).isActive = true

        let photos = ExtensionUI.button("Choose from Photos", action: UIAction { [weak self] _ in self?.choose(photos: true) })
        let files = ExtensionUI.button("Choose from Files", action: UIAction { [weak self] _ in self?.choose(photos: false) })
        let previewButton = ExtensionUI.button("Preview Cutout at Playhead", action: UIAction { [weak self] _ in self?.previewCurrentFrame() })
        let export = ExtensionUI.button("Export Cutout Video", action: UIAction { [weak self] action in
            self?.export(source: action.sender as? UIView)
        })
        let alphaRow = ExtensionUI.labeledSwitch("Transparent HEVC alpha", control: alphaSwitch)

        ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("Cut out a person from the selected video. Accurate mode is slower and uses more memory."),
            preview, photos, files, sourceLabel, quality, alphaRow, previewButton, cutoutPreview, progress, export, status
        ]), in: self)
    }

    private func choose(photos: Bool) {
        let picker = MediaSourcePicker(presenter: self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                self.sourceURL = url
                self.preview.load(url: url)
                self.sourceLabel.text = url.lastPathComponent
                self.status.text = "Ready. Move the playhead and preview a frame."
            case .failure(let error):
                ExtensionUI.alert(title: "Import failed", message: error.localizedDescription, from: self)
            }
        }
        self.picker = picker
        photos ? picker.presentPhotos() : picker.presentFiles()
    }

    private func previewCurrentFrame() {
        guard let sourceURL else {
            ExtensionUI.alert(title: "Choose a video", message: "Select a source video first.", from: self)
            return
        }
        let time = preview.currentTime
        let qualityValue = quality.selectedSegmentIndex
        status.text = "Generating cutout preview…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try PersonCutoutExporter().previewPNGData(url: sourceURL, time: time, quality: qualityValue)
                }.value
                self.cutoutPreview.image = UIImage(data: data)
                self.status.text = "Preview complete."
            } catch {
                self.status.text = "Preview failed."
                ExtensionUI.alert(title: "Cutout failed", message: error.localizedDescription, from: self)
            }
        }
    }

    private func export(source: UIView?) {
        guard let sourceURL else {
            ExtensionUI.alert(title: "Choose a video", message: "Select a source video first.", from: self)
            return
        }
        let options = PersonCutoutOptions(quality: quality.selectedSegmentIndex, outputAlpha: alphaSwitch.isOn)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("AE-Motion-Cutout-\(UUID().uuidString).mov")
        progress.progress = 0
        status.text = "Exporting cutout video…"

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try PersonCutoutExporter().export(
                        inputURL: sourceURL,
                        outputURL: output,
                        options: options
                    ) { value in
                        Task { @MainActor [weak self] in self?.progress.progress = Float(value) }
                    }
                }.value
                self.status.text = options.outputAlpha ? "Transparent cutout export complete." : "Green-background cutout export complete."
                ExtensionUI.share(fileURL: output, from: self, source: source)
            } catch {
                self.status.text = "Export failed."
                ExtensionUI.alert(title: "Cutout export failed", message: error.localizedDescription, from: self)
            }
        }
    }
}
#endif
