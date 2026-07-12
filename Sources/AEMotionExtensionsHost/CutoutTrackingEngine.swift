#if canImport(UIKit) && canImport(AVFoundation) && canImport(Vision)
import UIKit
import AVFoundation
import Vision

struct NormalizedTrackingRect: Codable, Sendable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + width }
    var maxY: Double { y + height }

    func clamped() -> NormalizedTrackingRect {
        let nx = min(max(x, 0), 1)
        let ny = min(max(y, 0), 1)
        let nw = min(max(width, 0.001), 1 - nx)
        let nh = min(max(height, 0.001), 1 - ny)
        return .init(x: nx, y: ny, width: nw, height: nh)
    }

    var visionRect: CGRect {
        let rect = clamped()
        return CGRect(
            x: rect.x,
            y: 1 - rect.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    init(visionRect: CGRect) {
        self.init(
            x: Double(visionRect.minX),
            y: Double(1 - visionRect.minY - visionRect.height),
            width: Double(visionRect.width),
            height: Double(visionRect.height)
        )
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

struct CutoutTrackSample: Codable, Sendable, Equatable {
    var time: Double
    var rect: NormalizedTrackingRect
    var confidence: Double
}

struct CutoutTrackingPath: Codable, Sendable, Equatable {
    var anchorTime: Double
    var anchorRect: NormalizedTrackingRect
    var samples: [CutoutTrackSample]

    func rect(at time: Double) -> NormalizedTrackingRect {
        guard !samples.isEmpty else { return anchorRect }
        let ordered = samples.sorted { $0.time < $1.time }
        if time <= ordered[0].time { return ordered[0].rect }
        if time >= ordered[ordered.count - 1].time { return ordered[ordered.count - 1].rect }

        var low = 0
        var high = ordered.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if ordered[middle].time <= time { low = middle }
            else { high = middle }
        }
        let a = ordered[low]
        let b = ordered[high]
        let span = max(0.000_001, b.time - a.time)
        let t = min(max((time - a.time) / span, 0), 1)
        return .init(
            x: a.rect.x + (b.rect.x - a.rect.x) * t,
            y: a.rect.y + (b.rect.y - a.rect.y) * t,
            width: a.rect.width + (b.rect.width - a.rect.width) * t,
            height: a.rect.height + (b.rect.height - a.rect.height) * t
        ).clamped()
    }
}

enum CutoutTrackingError: Error, LocalizedError, Sendable {
    case noSelection
    case noVideo
    case frameGenerationFailed
    case lostTracking(Double)

    var errorDescription: String? {
        switch self {
        case .noSelection:
            return "Draw a Keep Brush region or create a Box Select region before tracking."
        case .noVideo:
            return "The selected file has no video track."
        case .frameGenerationFailed:
            return "A frame could not be generated for object tracking."
        case .lostTracking(let time):
            return String(format: "Tracking confidence became too low near %.2f seconds.", time)
        }
    }
}

extension ManualMaskDefinition {
    func trackingSeedRect(padding: Double = 0.04) -> NormalizedTrackingRect? {
        let keepOperations = operations.filter {
            $0.kind == .keepStroke || $0.kind == .keepRectangle
        }
        let points = keepOperations.flatMap(\.points)
        guard let first = points.first else { return nil }

        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        let maxRadius = keepOperations.map(\.radius).max() ?? 0
        let margin = max(padding, maxRadius)
        minX -= margin
        minY -= margin
        maxX += margin
        maxY += margin

        if maxX - minX < 0.04 {
            let center = (minX + maxX) * 0.5
            minX = center - 0.02
            maxX = center + 0.02
        }
        if maxY - minY < 0.04 {
            let center = (minY + maxY) * 0.5
            minY = center - 0.02
            maxY = center + 0.02
        }

        return NormalizedTrackingRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        ).clamped()
    }

    func transformed(
        from anchor: NormalizedTrackingRect,
        to current: NormalizedTrackingRect
    ) -> ManualMaskDefinition {
        let source = anchor.clamped()
        let destination = current.clamped()
        let scaleX = destination.width / max(0.000_001, source.width)
        let scaleY = destination.height / max(0.000_001, source.height)
        let radiusScale = max(0.25, min(4, (scaleX + scaleY) * 0.5))

        let transformedOperations = operations.map { operation in
            let points = operation.points.map { point in
                let localX = (point.x - source.x) / max(0.000_001, source.width)
                let localY = (point.y - source.y) / max(0.000_001, source.height)
                return NormalizedMaskPoint(
                    x: min(max(destination.x + localX * destination.width, 0), 1),
                    y: min(max(destination.y + localY * destination.height, 0), 1)
                )
            }
            return ManualMaskOperation(
                kind: operation.kind,
                points: points,
                radius: min(max(operation.radius * radiusScale, 0.003), 0.30)
            )
        }
        return ManualMaskDefinition(operations: transformedOperations)
    }
}

final class CutoutTrackingEngine: @unchecked Sendable {
    func track(
        inputURL: URL,
        anchorTime: Double,
        seedRect: NormalizedTrackingRect,
        samplesPerSecond: Double,
        accurate: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) throws -> CutoutTrackingPath {
        let asset = AVURLAsset(url: inputURL)
        guard asset.tracks(withMediaType: .video).first != nil else {
            throw CutoutTrackingError.noVideo
        }
        let duration = max(0.001, asset.duration.seconds)
        let clampedAnchor = min(max(anchorTime, 0), duration)
        let fps = min(max(samplesPerSecond, 4), 30)
        let step = 1.0 / fps

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: min(step * 0.45, 0.02), preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: min(step * 0.45, 0.02), preferredTimescale: 600)

        let initialObservation = VNDetectedObjectObservation(boundingBox: seedRect.visionRect)
        var samples = [CutoutTrackSample(
            time: clampedAnchor,
            rect: seedRect.clamped(),
            confidence: 1
        )]

        let forwardTimes = strideTimes(from: clampedAnchor + step, through: duration, step: step)
        let backwardTimes = strideTimes(from: clampedAnchor - step, through: 0, step: -step)
        let total = max(1, forwardTimes.count + backwardTimes.count)
        var completed = 0

        let forward = try trackSequence(
            times: forwardTimes,
            generator: generator,
            initialObservation: initialObservation,
            accurate: accurate
        ) { value in
            completed += 1
            progress(Double(completed) / Double(total))
        }
        samples.append(contentsOf: forward)

        let backward = try trackSequence(
            times: backwardTimes,
            generator: generator,
            initialObservation: initialObservation,
            accurate: accurate
        ) { value in
            completed += 1
            progress(Double(completed) / Double(total))
        }
        samples.append(contentsOf: backward)

        samples.sort { $0.time < $1.time }
        progress(1)
        return CutoutTrackingPath(
            anchorTime: clampedAnchor,
            anchorRect: seedRect.clamped(),
            samples: samples
        )
    }

    private func trackSequence(
        times: [Double],
        generator: AVAssetImageGenerator,
        initialObservation: VNDetectedObjectObservation,
        accurate: Bool,
        onSample: (CutoutTrackSample) -> Void
    ) throws -> [CutoutTrackSample] {
        guard !times.isEmpty else { return [] }
        let sequence = VNSequenceRequestHandler()
        var observation = initialObservation
        var output: [CutoutTrackSample] = []
        output.reserveCapacity(times.count)

        for time in times {
            var actual = CMTime.invalid
            let image = try generator.copyCGImage(
                at: CMTime(seconds: max(0, time), preferredTimescale: 600),
                actualTime: &actual
            )
            let request = VNTrackObjectRequest(detectedObjectObservation: observation)
            request.trackingLevel = accurate ? .accurate : .fast
            try sequence.perform([request], on: image)
            guard let result = request.results?.first as? VNDetectedObjectObservation else {
                throw CutoutTrackingError.lostTracking(time)
            }
            if result.confidence < 0.18 {
                throw CutoutTrackingError.lostTracking(time)
            }
            observation = result
            let sample = CutoutTrackSample(
                time: max(0, actual.seconds.isFinite ? actual.seconds : time),
                rect: NormalizedTrackingRect(visionRect: result.boundingBox).clamped(),
                confidence: Double(result.confidence)
            )
            output.append(sample)
            onSample(sample)
        }
        return output
    }

    private func strideTimes(from start: Double, through end: Double, step: Double) -> [Double] {
        guard step != 0 else { return [] }
        if step > 0, start > end { return [] }
        if step < 0, start < end { return [] }
        var values: [Double] = []
        var current = start
        if step > 0 {
            while current <= end + 0.000_001 {
                values.append(current)
                current += step
            }
        } else {
            while current >= end - 0.000_001 {
                values.append(max(0, current))
                current += step
            }
        }
        return values
    }
}
#endif
