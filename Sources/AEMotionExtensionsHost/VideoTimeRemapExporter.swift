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
    var includeAudio: Bool = true
    var preservePitch: Bool = true
    var audioSegmentRate: Double = 24
}

enum VideoTimeRemapExportError: Error, LocalizedError, Sendable {
    case noVideoTrack
    case invalidDimensions
    case cannotCreateWriter
    case cannotCreatePixelBuffer
    case frameGenerationFailed(Double)
    case appendFailed(Double)
    case writerFailed(String)
    case compositionFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "The selected file has no video track."
        case .invalidDimensions: return "The video dimensions are invalid."
        case .cannotCreateWriter: return "The video writer could not be created."
        case .cannotCreatePixelBuffer: return "A render buffer could not be allocated."
        case .frameGenerationFailed(let time): return "Could not decode the source near \(time) seconds."
        case .appendFailed(let time): return "Could not append the frame at \(time) seconds."
        case .writerFailed(let reason): return reason
        case .compositionFailed(let reason): return reason
        case .exportFailed(let reason): return reason
        }
    }
}

/// Renders a variable-speed video frame-by-frame, then optionally rebuilds the
/// positive-speed audio path from short scaled segments. The export session's
/// spectral time-pitch algorithm preserves pitch for supported forward segments.
/// Freeze and reverse segments are intentionally silent because AVFoundation's
/// composition time-scaling does not reverse PCM samples.
final class VideoTimeRemapExporter: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func export(
        inputURL: URL,
        outputURL: URL,
        curve: SpeedCurve,
        options: VideoTimeRemapExportOptions,
        cancellationToken: RenderCancellationToken? = nil,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        try cancellationToken?.checkCancellation()
        let temporaryVideo = RenderTemporaryFiles.makeURL(label: "Retimed-Video")
        defer { try? FileManager.default.removeItem(at: temporaryVideo) }

        try renderVideoOnly(
            inputURL: inputURL,
            outputURL: temporaryVideo,
            curve: curve,
            options: options,
            cancellationToken: cancellationToken
        ) { value in
            progress(value * (options.includeAudio ? 0.82 : 1.0))
        }

        guard options.includeAudio else {
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.moveItem(at: temporaryVideo, to: outputURL)
            progress(1)
            return
        }

        try muxVariableRateAudio(
            sourceURL: inputURL,
            renderedVideoURL: temporaryVideo,
            outputURL: outputURL,
            curve: curve,
            options: options,
            cancellationToken: cancellationToken
        )
        progress(1)
    }

    private func renderVideoOnly(
        inputURL: URL,
        outputURL: URL,
        curve: SpeedCurve,
        options: VideoTimeRemapExportOptions,
        cancellationToken: RenderCancellationToken?,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        try cancellationToken?.checkCancellation()
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
        let sourceWidth = Int(abs(transformed.width).rounded())
        let sourceHeight = Int(abs(transformed.height).rounded())
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw VideoTimeRemapExportError.invalidDimensions
        }
        let dimensions = RenderSizePolicy.constrained(width: sourceWidth, height: sourceHeight)
        let width = dimensions.width
        let height = dimensions.height
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
        generator.maximumSize = CGSize(width: width, height: height)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1.0 / max(1, options.frameRate), preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore

        for (index, sample) in samples.enumerated() {
            try cancellationToken?.checkCancellation()
            while !input.isReadyForMoreMediaData {
                try cancellationToken?.checkCancellation()
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
            let sourceImage = CIImage(cgImage: image)
            let scaleX = CGFloat(width) / max(1, sourceImage.extent.width)
            let scaleY = CGFloat(height) / max(1, sourceImage.extent.height)
            let renderedImage = sourceImage
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                .cropped(to: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            context.render(
                renderedImage,
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
        while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
            do {
                try cancellationToken?.checkCancellation()
            } catch {
                writer.cancelWriting()
                throw error
            }
        }
        guard writer.status == .completed else {
            throw VideoTimeRemapExportError.writerFailed(
                writer.error?.localizedDescription ?? "finishWriting failed"
            )
        }
    }

    private func muxVariableRateAudio(
        sourceURL: URL,
        renderedVideoURL: URL,
        outputURL: URL,
        curve: SpeedCurve,
        options: VideoTimeRemapExportOptions,
        cancellationToken: RenderCancellationToken?
    ) throws {
        try cancellationToken?.checkCancellation()
        let sourceAsset = AVURLAsset(url: sourceURL)
        guard let sourceAudio = sourceAsset.tracks(withMediaType: .audio).first else {
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.copyItem(at: renderedVideoURL, to: outputURL)
            return
        }
        let renderedAsset = AVURLAsset(url: renderedVideoURL)
        guard let renderedVideo = renderedAsset.tracks(withMediaType: .video).first else {
            throw VideoTimeRemapExportError.noVideoTrack
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoTimeRemapExportError.compositionFailed("Could not create composition tracks.")
        }

        let outputRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: options.outputDuration, preferredTimescale: 600)
        )
        do {
            try videoTrack.insertTimeRange(outputRange, of: renderedVideo, at: .zero)
            videoTrack.preferredTransform = renderedVideo.preferredTransform
        } catch {
            throw VideoTimeRemapExportError.compositionFailed("Could not insert rendered video: \(error.localizedDescription)")
        }

        let sourceDuration = max(0, sourceAsset.duration.seconds)
        let sampleRate = max(4, min(120, options.audioSegmentRate))
        let segmentCount = max(1, Int(ceil(options.outputDuration * sampleRate)))
        var destinationCursor = CMTime.zero

        for index in 0..<segmentCount {
            try cancellationToken?.checkCancellation()
            let outputStart = options.outputDuration * Double(index) / Double(segmentCount)
            let outputEnd = options.outputDuration * Double(index + 1) / Double(segmentCount)
            let outputSegmentDuration = outputEnd - outputStart
            guard outputSegmentDuration > 0 else { continue }

            let sourceStart = curve.sourceTime(at: outputStart)
            let sourceEnd = curve.sourceTime(at: outputEnd)
            let sourceDelta = sourceEnd - sourceStart
            let destinationDuration = CMTime(seconds: outputSegmentDuration, preferredTimescale: 600)

            if sourceDelta > 0.0001 {
                let clampedStart = min(max(sourceStart, 0), sourceDuration)
                let clampedEnd = min(max(sourceEnd, 0), sourceDuration)
                let duration = max(0, clampedEnd - clampedStart)
                if duration > 0.0001 {
                    let sourceRange = CMTimeRange(
                        start: CMTime(seconds: clampedStart, preferredTimescale: 600),
                        duration: CMTime(seconds: duration, preferredTimescale: 600)
                    )
                    do {
                        try audioTrack.insertTimeRange(sourceRange, of: sourceAudio, at: destinationCursor)
                        let insertedRange = CMTimeRange(start: destinationCursor, duration: sourceRange.duration)
                        audioTrack.scaleTimeRange(insertedRange, toDuration: destinationDuration)
                    } catch {
                        throw VideoTimeRemapExportError.compositionFailed("Could not build retimed audio: \(error.localizedDescription)")
                    }
                }
            }
            destinationCursor = destinationCursor + destinationDuration
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoTimeRemapExportError.exportFailed("Could not create the final export session.")
        }
        session.outputURL = outputURL
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = false
        session.audioTimePitchAlgorithm = options.preservePitch ? .spectral : .varispeed

        let semaphore = DispatchSemaphore(value: 0)
        session.exportAsynchronously { semaphore.signal() }
        while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
            do {
                try cancellationToken?.checkCancellation()
            } catch {
                session.cancelExport()
                throw error
            }
        }
        guard session.status == .completed else {
            throw VideoTimeRemapExportError.exportFailed(
                session.error?.localizedDescription ?? "Final audio/video export failed."
            )
        }
    }
}
#endif
