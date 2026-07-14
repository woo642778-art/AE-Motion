import Foundation

public struct GestureSample: Equatable, Codable, Sendable {
    public var time: Double
    public var x: Double
    public var y: Double
    public var rotation: Double
    public var scale: Double
    public init(time: Double, x: Double, y: Double, rotation: Double = 0, scale: Double = 1) { self.time = time; self.x = x; self.y = y; self.rotation = rotation; self.scale = scale }
}

public struct GestureRecording: Equatable, Codable, Sendable {
    public var duration: Double
    public var position: AnimatableProperty
    public var rotation: AnimatableProperty
    public var scale: AnimatableProperty
    public init(duration: Double, position: AnimatableProperty, rotation: AnimatableProperty, scale: AnimatableProperty) { self.duration = max(duration, 0); self.position = position; self.rotation = rotation; self.scale = scale }
}

public enum MotionCleanup {
    public static func smooth(_ samples: [GestureSample], radius: Int = 2) -> [GestureSample] {
        guard samples.count > 2, radius > 0 else { return samples }
        return samples.indices.map { index in
            if index == samples.startIndex || index == samples.index(before: samples.endIndex) { return samples[index] }
            let lower = max(samples.startIndex, index - radius), upper = min(samples.index(before: samples.endIndex), index + radius)
            let window = samples[lower...upper], count = Double(window.count)
            return GestureSample(time: samples[index].time, x: window.reduce(0) { $0 + $1.x } / count, y: window.reduce(0) { $0 + $1.y } / count, rotation: circularMean(window.map(\.rotation)), scale: window.reduce(0) { $0 + $1.scale } / count)
        }
    }
    public static func simplify(_ samples: [GestureSample], tolerance: Double = 0.75) -> [GestureSample] {
        guard samples.count > 2, tolerance > 0 else { return samples }
        return ramerDouglasPeucker(samples, tolerance: tolerance).sorted { $0.time < $1.time }
    }
    public static func cleaned(_ samples: [GestureSample], smoothingRadius: Int = 2, simplificationTolerance: Double = 0.75, alignStartToZero: Bool = true, loop: Bool = false) -> [GestureSample] {
        guard !samples.isEmpty else { return [] }
        var result = simplify(smooth(samples, radius: smoothingRadius), tolerance: simplificationTolerance)
        if alignStartToZero, let first = result.first { result = result.map { GestureSample(time: max(0, $0.time - first.time), x: $0.x, y: $0.y, rotation: $0.rotation, scale: $0.scale) } }
        if loop, result.count > 1, let first = result.first, let last = result.last { result[result.count - 1] = GestureSample(time: last.time, x: first.x, y: first.y, rotation: first.rotation, scale: first.scale) }
        return result
    }
    public static func recording(from samples: [GestureSample], cleanup: Bool = true, loop: Bool = false) -> GestureRecording {
        let source = cleanup ? cleaned(samples, loop: loop) : samples
        return GestureRecording(
            duration: source.last?.time ?? 0,
            position: AnimatableProperty(id: "transform.position", displayName: "Position", defaultValue: .point(x: source.first?.x ?? 0, y: source.first?.y ?? 0), curve: AnimationKeyframeCurve(keyframes: source.map { Keyframe(time: $0.time, value: .point(x: $0.x, y: $0.y), interpolation: .autoBezier) })),
            rotation: AnimatableProperty(id: "transform.rotation", displayName: "Rotation", defaultValue: .angle(source.first?.rotation ?? 0), curve: AnimationKeyframeCurve(keyframes: source.map { Keyframe(time: $0.time, value: .angle($0.rotation), interpolation: .autoBezier) })),
            scale: AnimatableProperty(id: "transform.scale", displayName: "Scale", defaultValue: .scalar(source.first?.scale ?? 1), curve: AnimationKeyframeCurve(keyframes: source.map { Keyframe(time: $0.time, value: .scalar($0.scale), interpolation: .autoBezier) }))
        )
    }
    private static func ramerDouglasPeucker(_ samples: [GestureSample], tolerance: Double) -> [GestureSample] {
        guard samples.count > 2 else { return samples }
        let first = samples[0], last = samples[samples.count - 1]
        var maxDistance = 0.0, maxIndex = 0
        for index in 1..<(samples.count - 1) { let distance = perpendicularDistance(samples[index], start: first, end: last); if distance > maxDistance { maxDistance = distance; maxIndex = index } }
        guard maxDistance > tolerance else { return [first, last] }
        let left = ramerDouglasPeucker(Array(samples[0...maxIndex]), tolerance: tolerance), right = ramerDouglasPeucker(Array(samples[maxIndex...]), tolerance: tolerance)
        return Array(left.dropLast()) + right
    }
    private static func perpendicularDistance(_ point: GestureSample, start: GestureSample, end: GestureSample) -> Double {
        let dx = end.x - start.x, dy = end.y - start.y
        if abs(dx) + abs(dy) < 1e-12 { return hypot(point.x - start.x, point.y - start.y) }
        return abs(dy * point.x - dx * point.y + end.x * start.y - end.y * start.x) / hypot(dx, dy)
    }
    private static func circularMean(_ angles: [Double]) -> Double {
        guard !angles.isEmpty else { return 0 }
        let radians = angles.map { $0 * Double.pi / 180 }
        return atan2(radians.reduce(0) { $0 + sin($1) }, radians.reduce(0) { $0 + cos($1) }) * 180 / Double.pi
    }
}

public struct GestureRecorder: Sendable {
    public var minimumSampleInterval: Double
    private var samples: [GestureSample]
    public init(minimumSampleInterval: Double = 1.0 / 60.0) { self.minimumSampleInterval = max(minimumSampleInterval, 1.0 / 240.0); self.samples = [] }
    public mutating func append(_ sample: GestureSample) {
        guard sample.time.isFinite, sample.x.isFinite, sample.y.isFinite, sample.rotation.isFinite, sample.scale.isFinite else { return }
        if let last = samples.last, sample.time - last.time < minimumSampleInterval { return }
        samples.append(sample)
    }
    public mutating func reset() { samples.removeAll(keepingCapacity: true) }
    public func finish(cleanup: Bool = true, loop: Bool = false) -> GestureRecording { MotionCleanup.recording(from: samples, cleanup: cleanup, loop: loop) }
    public var sampleCount: Int { samples.count }
}
