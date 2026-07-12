#if canImport(UIKit) && canImport(AVFoundation) && canImport(CoreImage) && canImport(CoreVideo)
import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import AEMotionExtensionsCore

struct VideoTimeRemapExportOptions: Sendable {
    var outputDuration: Double
    var frameRate: Double
    var videoCodec: AVVideoCodecType = .h264
}

enum VideoTimeRemapExportError: Error, LocalizedError, Sendable {
    case noVideoTrack
    case invalidDimensions
    case cannotCreateWriter
    case cannotCreatePixelBuffer
    case frameGenerationFailed(Double)
    case appendFailed(Double)
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "The selected file has no video track."
        case .invalidDimensions: return "The video dimensions are invalid."
        case .cannotCreateWriter: return "The video writer could not be created."
        case .cannotCreatePixelBuffer: return "A render buffer could not be allocated."
        case .frameGenerationFailed(let time): return "Could not decode the source near \(time) seconds."
        case .appendFailed(let time): return "Could not append the frame at \(time) seconds."
        case .writerFailed(let reason): return reason
        }
    }
}

/// Video-only exporter. Audio is intentionally omitted until a pitch-preserving
/// variable-rate audio graph is added.
final class VideoTimeRemapExporter: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func export(
        inputURL: URL,
        outputURL: URL,
        curve: SpeedCurve,
        options: VideoTimeRemapExportOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let samples = try SpeedFrameSamplePlanner.plan(
            curve: curve,
            outputDuration: options.outputDuration,
            frameRate: options.frameRate
        )
        let asset = AVURLAsset(url: inputURL)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw VideoTimeRemapExportError.noVideoTrack
        }
        let transformed = track.naturalSize.applying(track.preferredTransform)
        let width = Int(abs(transformed.width).rounded())
        let height = Int(abs(transformed.height).rounded())
        guard width > 0, height > 0 else {
            throw VideoTimeRemapExportError.invalidDimensions
        }
        let sourceDuration = asset.duration.seconds

        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: options.videoCodec,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
        )
        guard writer.canAdd(input) else {
            throw VideoTimeRemapExportError.cannotCreateWriter
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw VideoTimeRemapExportError.writerFailed(
                writer.error?.localizedDescription ?? "startWriting failed"
            )
        }
        writer.startSession(atSourceTime: .zero)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        for (index, sample) in samples.enumerated() {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.002)
            }
            let clamped = min(max(sample.sourceTime, 0), max(0, sourceDuration))
            var actual = CMTime.invalid
            let sourceTime = CMTime(seconds: clamped, preferredTimescale: 600)
            let image: CGImage
            do {
                image = try generator.copyCGImage(at: sourceTime, actualTime: &actual)
            } catch {
                throw VideoTimeRemapExportError.frameGenerationFailed(clamped)
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw VideoTimeRemapExportError.cannotCreatePixelBuffer
            }
            var optionalBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
                  let buffer = optionalBuffer else {
                throw VideoTimeRemapExportError.cannotCreatePixelBuffer
            }
            context.render(
                CIImage(cgImage: image),
                to: buffer,
                bounds: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            let presentationTime = CMTime(seconds: sample.outputTime, preferredTimescale: 600)
            guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
                throw VideoTimeRemapExportError.appendFailed(sample.outputTime)
            }
            progress(Double(index + 1) / Double(max(1, samples.count)))
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        guard writer.status == .completed else {
            throw VideoTimeRemapExportError.writerFailed(
                writer.error?.localizedDescription ?? "finishWriting failed"
            )
        }
    }
}
#endif
