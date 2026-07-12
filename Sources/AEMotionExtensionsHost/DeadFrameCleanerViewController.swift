#if canImport(UIKit) && canImport(AVFoundation) && canImport(CoreGraphics)
import UIKit
import AVFoundation
import CoreGraphics

struct DeadFrameRange: Sendable, Equatable {
    var start: Double
    var end: Double
}

enum DeadFrameCleanerError: Error, LocalizedError, Sendable {
    case noVideo
    case noFrames
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideo: return "The selected file has no video track."
        case .noFrames: return "No frames could be analyzed."
        case .exportFailed(let message): return message
        }
    }
}

enum DeadFrameAnalyzer {
    static func analyze(
        url: URL,
        frameRate: Double,
        threshold: Double,
        progress: @escaping @Sendable (Double) -> Void
    ) throws -> [DeadFrameRange] {
        let asset = AVURLAsset(url: url)
        guard asset.tracks(withMediaType: .video).first != nil else { throw DeadFrameCleanerError.noVideo }
        let duration = max(0, asset.duration.seconds)
        let fps = max(1, min(120, frameRate))
        let total = max(1, min(6000, Int(floor(duration * fps))))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 64, height: 64)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore

        var previous: [UInt8]?
        var duplicates: [DeadFrameRange] = []
        let frameDuration = 1.0 / fps

        for index in 0..<total {
            let time = min(duration, Double(index) / fps)
            var actual = CMTime.invalid
            guard let image = try? generator.copyCGImage(
                at: CMTime(seconds: time, preferredTimescale: 600),
                actualTime: &actual
            ) else { continue }
            let signature = grayscaleSignature(image)
            if let previous {
                let difference = meanDifference(previous, signature)
                if difference <= threshold {
                    duplicates.append(.init(start: time, end: min(duration, time + frameDuration)))
                }
            }
            previous = signature
            progress(Double(index + 1) / Double(total))
        }
        guard previous != nil else { throw DeadFrameCleanerError.noFrames }
        return merge(duplicates)
    }

    static func exportRemovingRanges(
        sourceURL: URL,
        outputURL: URL,
        removeRanges: [DeadFrameRange]
    ) throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let sourceVideo = asset.tracks(withMediaType: .video).first else {
            throw DeadFrameCleanerError.noVideo
        }
        let sourceAudio = asset.tracks(withMediaType: .audio).first
        let duration = max(0, asset.duration.seconds)
        let keep = complement(of: merge(removeRanges), duration: duration)

        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw DeadFrameCleanerError.exportFailed("Could not create a video composition track.")
        }
        let audio = sourceAudio.flatMap { _ in
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        video.preferredTransform = sourceVideo.preferredTransform

        var cursor = CMTime.zero
        for range in keep where range.end > range.start {
            let timeRange = CMTimeRange(
                start: CMTime(seconds: range.start, preferredTimescale: 600),
                duration: CMTime(seconds: range.end - range.start, preferredTimescale: 600)
            )
            do {
                try video.insertTimeRange(timeRange, of: sourceVideo, at: cursor)
                if let sourceAudio, let audio {
                    try audio.insertTimeRange(timeRange, of: sourceAudio, at: cursor)
                }
            } catch {
                throw DeadFrameCleanerError.exportFailed("Could not build the cleaned timeline: \(error.localizedDescription)")
            }
            cursor = cursor + timeRange.duration
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw DeadFrameCleanerError.exportFailed("Could not create the cleaner export session.")
        }
        session.outputURL = outputURL
        session.outputFileType = .mov
        let semaphore = DispatchSemaphore(value: 0)
        session.exportAsynchronously { semaphore.signal() }
        semaphore.wait()
        guard session.status == .completed else {
            throw DeadFrameCleanerError.exportFailed(
                session.error?.localizedDescription ?? "Dead-frame export failed."
            )
        }
    }

    private static func grayscaleSignature(_ image: CGImage) -> [UInt8] {
        let width = 24
        let height = 14
        var bytes = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        bytes.withUnsafeMutableBytes { storage in
            guard let context = CGContext(
                data: storage.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    private static func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        let total = zip(a, b).reduce(0.0) { partial, pair in
            partial + abs(Double(pair.0) - Double(pair.1)) / 255.0
        }
        return total / Double(a.count)
    }

    private static func merge(_ ranges: [DeadFrameRange]) -> [DeadFrameRange] {
        let sorted = ranges.sorted { $0.start < $1.start }
        var result: [DeadFrameRange] = []
        for range in sorted {
            guard range.end > range.start else { continue }
            if let last = result.last, range.start <= last.end + 0.0001 {
                result[result.count - 1].end = max(last.end, range.end)
            } else {
                result.append(range)
            }
        }
        return result
    }

    private static func complement(of ranges: [DeadFrameRange], duration: Double) -> [DeadFrameRange] {
        var cursor = 0.0
        var result: [DeadFrameRange] = []
        for range in ranges {
            let start = min(max(range.start, 0), duration)
            let end = min(max(range.end, 0), duration)
            if start > cursor { result.append(.init(start: cursor, end: start)) }
            cursor = max(cursor, end)
        }
        if cursor < duration { result.append(.init(start: cursor, end: duration)) }
        return result
    }
}

@MainActor
final class DeadFrameCleanerViewController: UIViewController {
    private let preview = VideoPreviewPanel()
    private let sourceLabel = ExtensionUI.label("No source video selected.")
    private let fpsField = ExtensionUI.field("Analysis FPS", value: "30")
    private let thresholdField = ExtensionUI.field("Difference threshold 0–1", value: "0.012")
    private let progress = UIProgressView(progressViewStyle: .default)
    private let status = ExtensionUI.label("Detects consecutive near-identical frames and removes them while keeping audio aligned.")
    private var picker: MediaSourcePicker?
    private var sourceURL: URL?
    private var ranges: [DeadFrameRange] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Dead Frame Cleaner"
        view.backgroundColor = .systemBackground

        let photos = ExtensionUI.button("Choose from Photos", action: UIAction { [weak self] _ in self?.choose(photos: true) })
        let files = ExtensionUI.button("Choose from Files", action: UIAction { [weak self] _ in self?.choose(photos: false) })
        let analyze = ExtensionUI.button("Analyze Dead Frames", action: UIAction { [weak self] _ in self?.analyze() })
        let export = ExtensionUI.button("Export Cleaned Video", action: UIAction { [weak self] action in
            self?.export(source: action.sender as? UIView)
        })

        ExtensionUI.installScrollStack(ExtensionUI.stack([
            ExtensionUI.label("Automatic duplicate/dead-frame removal for clips that contain repeated frames."),
            preview, photos, files, sourceLabel, fpsField, thresholdField, progress, analyze, export, status
        ]), in: self)
    }

    private func choose(photos: Bool) {
        let picker = MediaSourcePicker(presenter: self) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                self.sourceURL = url
                self.ranges = []
                self.preview.load(url: url)
                self.sourceLabel.text = url.lastPathComponent
                self.status.text = "Ready to analyze."
            case .failure(let error):
                ExtensionUI.alert(title: "Import failed", message: error.localizedDescription, from: self)
            }
        }
        self.picker = picker
        photos ? picker.presentPhotos() : picker.presentFiles()
    }

    private func analyze() {
        guard let sourceURL else {
            ExtensionUI.alert(title: "Choose a video", message: "Select a source video first.", from: self)
            return
        }
        let fps = max(1, min(120, Double(fpsField.text ?? "") ?? 30))
        let threshold = max(0, min(1, Double(thresholdField.text ?? "") ?? 0.012))
        progress.progress = 0
        status.text = "Analyzing frames…"

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try DeadFrameAnalyzer.analyze(url: sourceURL, frameRate: fps, threshold: threshold) { value in
                        Task { @MainActor [weak self] in self?.progress.progress = Float(value) }
                    }
                }.value
                self.ranges = result
                let removed = result.reduce(0.0) { $0 + max(0, $1.end - $1.start) }
                self.status.text = "Detected \(result.count) duplicate ranges · approximately \(String(format: "%.3f", removed)) s removable."
            } catch {
                self.status.text = "Analysis failed."
                ExtensionUI.alert(title: "Analysis failed", message: error.localizedDescription, from: self)
            }
        }
    }

    private func export(source: UIView?) {
        guard let sourceURL else {
            ExtensionUI.alert(title: "Choose a video", message: "Select a source video first.", from: self)
            return
        }
        guard !ranges.isEmpty else {
            ExtensionUI.alert(title: "Analyze first", message: "No dead-frame ranges are available yet.", from: self)
            return
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("AE-Motion-DeadFrames-Cleaned-\(UUID().uuidString).mov")
        let ranges = self.ranges
        status.text = "Exporting cleaned video…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try DeadFrameAnalyzer.exportRemovingRanges(
                        sourceURL: sourceURL,
                        outputURL: output,
                        removeRanges: ranges
                    )
                }.value
                self.status.text = "Cleaned export complete."
                ExtensionUI.share(fileURL: output, from: self, source: source)
            } catch {
                self.status.text = "Export failed."
                ExtensionUI.alert(title: "Export failed", message: error.localizedDescription, from: self)
            }
        }
    }
}
#endif
