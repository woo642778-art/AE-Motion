import Foundation

public struct PropertyID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { self.rawValue = value }
    public var description: String { rawValue }
}

public enum KeyframeValue: Equatable, Codable, Sendable {
    case scalar(Double)
    case point(x: Double, y: Double)
    case color(r: Double, g: Double, b: Double, a: Double)
    case angle(Double)

    public var components: [Double] {
        switch self {
        case let .scalar(value), let .angle(value): return [value]
        case let .point(x, y): return [x, y]
        case let .color(r, g, b, a): return [r, g, b, a]
        }
    }
    public var magnitude: Double { sqrt(components.reduce(0) { $0 + $1 * $1 }) }
    public func interpolated(to other: KeyframeValue, progress: Double, clamping: Bool = true) -> KeyframeValue {
        let t = clamping ? min(max(progress, 0), 1) : progress
        switch (self, other) {
        case let (.scalar(a), .scalar(b)): return .scalar(a + (b - a) * t)
        case let (.angle(a), .angle(b)): return .angle(a + shortestAngleDelta(from: a, to: b) * t)
        case let (.point(ax, ay), .point(bx, by)): return .point(x: ax + (bx - ax) * t, y: ay + (by - ay) * t)
        case let (.color(ar, ag, ab, aa), .color(br, bg, bb, ba)):
            return .color(r: ar + (br - ar) * t, g: ag + (bg - ag) * t, b: ab + (bb - ab) * t, a: aa + (ba - aa) * t)
        default: return t < 0.5 ? self : other
        }
    }
    public func adding(_ other: KeyframeValue) -> KeyframeValue? {
        switch (self, other) {
        case let (.scalar(a), .scalar(b)): return .scalar(a + b)
        case let (.angle(a), .angle(b)): return .angle(a + b)
        case let (.point(ax, ay), .point(bx, by)): return .point(x: ax + bx, y: ay + by)
        case let (.color(ar, ag, ab, aa), .color(br, bg, bb, ba)): return .color(r: ar + br, g: ag + bg, b: ab + bb, a: aa + ba)
        default: return nil
        }
    }
    public func scaled(by factor: Double) -> KeyframeValue {
        switch self {
        case let .scalar(value): return .scalar(value * factor)
        case let .angle(value): return .angle(value * factor)
        case let .point(x, y): return .point(x: x * factor, y: y * factor)
        case let .color(r, g, b, a): return .color(r: r * factor, g: g * factor, b: b * factor, a: a * factor)
        }
    }
    public func distance(to other: KeyframeValue) -> Double {
        let lhs = components, rhs = other.components
        guard lhs.count == rhs.count else { return .infinity }
        return sqrt(zip(lhs, rhs).reduce(0) { $0 + pow($1.0 - $1.1, 2) })
    }
    private func shortestAngleDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
        return delta
    }
}

public struct BezierHandle: Equatable, Codable, Sendable {
    public var timeOffset: Double
    public var valueOffset: Double
    public init(timeOffset: Double = 0.3333333333, valueOffset: Double = 0) { self.timeOffset = timeOffset; self.valueOffset = valueOffset }
}

public enum InterpolationMode: String, CaseIterable, Codable, Sendable { case hold, linear, autoBezier, bezier, back, bounce, elastic }
public enum ExtrapolationMode: String, CaseIterable, Codable, Sendable { case clamp, linear, cycle, pingPong }

public struct Keyframe: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var time: Double
    public var value: KeyframeValue
    public var interpolation: InterpolationMode
    public var inHandle: BezierHandle
    public var outHandle: BezierHandle
    public init(id: UUID = UUID(), time: Double, value: KeyframeValue, interpolation: InterpolationMode = .autoBezier, inHandle: BezierHandle = .init(timeOffset: -0.3333333333), outHandle: BezierHandle = .init(timeOffset: 0.3333333333)) {
        self.id = id; self.time = time; self.value = value; self.interpolation = interpolation; self.inHandle = inHandle; self.outHandle = outHandle
    }
}

public struct AnimationKeyframeCurve: Equatable, Codable, Sendable {
    public private(set) var keyframes: [Keyframe]
    public var preExtrapolation: ExtrapolationMode
    public var postExtrapolation: ExtrapolationMode
    public init(keyframes: [Keyframe] = [], preExtrapolation: ExtrapolationMode = .clamp, postExtrapolation: ExtrapolationMode = .clamp) {
        self.keyframes = Self.normalized(keyframes); self.preExtrapolation = preExtrapolation; self.postExtrapolation = postExtrapolation
    }
    public mutating func replaceKeyframes(_ keyframes: [Keyframe]) { self.keyframes = Self.normalized(keyframes) }
    public mutating func upsert(_ keyframe: Keyframe, tolerance: Double = 1e-9) {
        if let index = keyframes.firstIndex(where: { abs($0.time - keyframe.time) <= tolerance }) { keyframes[index] = keyframe } else { keyframes.append(keyframe) }
        keyframes = Self.normalized(keyframes)
    }
    public mutating func remove(ids: Set<UUID>) { keyframes.removeAll { ids.contains($0.id) } }
    public func value(at rawTime: Double, fallback: KeyframeValue) -> KeyframeValue {
        guard let first = keyframes.first else { return fallback }
        guard keyframes.count > 1, let last = keyframes.last else { return first.value }
        let time = remappedTime(rawTime, first: first.time, last: last.time)
        if time <= first.time { return extrapolatedValue(at: time, boundary: .pre, fallback: fallback) }
        if time >= last.time { return extrapolatedValue(at: time, boundary: .post, fallback: fallback) }
        guard let upperIndex = keyframes.firstIndex(where: { $0.time >= time }), upperIndex > 0 else { return last.value }
        let lower = keyframes[upperIndex - 1], upper = keyframes[upperIndex]
        let local = min(max((time - lower.time) / max(upper.time - lower.time, 1e-12), 0), 1)
        return lower.value.interpolated(to: upper.value, progress: easingProgress(local, mode: lower.interpolation, lower: lower, upper: upper))
    }
    public func speed(at time: Double, fallback: KeyframeValue, delta: Double = 1.0 / 600.0) -> Double {
        guard delta > 0 else { return 0 }
        let distance = value(at: time - delta, fallback: fallback).distance(to: value(at: time + delta, fallback: fallback))
        return distance.isFinite ? distance / (delta * 2) : 0
    }
    public func valueRange(fallback: KeyframeValue) -> ClosedRange<Double> {
        let values = keyframes.flatMap { $0.value.components }
        guard let minimum = values.min(), let maximum = values.max() else { let value = fallback.components.first ?? 0; return value...value }
        return minimum...maximum
    }
    private enum Boundary { case pre, post }
    private func extrapolatedValue(at time: Double, boundary: Boundary, fallback: KeyframeValue) -> KeyframeValue {
        guard let first = keyframes.first, let last = keyframes.last else { return fallback }
        let mode = boundary == .pre ? preExtrapolation : postExtrapolation
        switch mode {
        case .clamp, .cycle, .pingPong: return boundary == .pre ? first.value : last.value
        case .linear:
            guard keyframes.count >= 2 else { return boundary == .pre ? first.value : last.value }
            let a = boundary == .pre ? keyframes[0] : keyframes[keyframes.count - 2]
            let b = boundary == .pre ? keyframes[1] : keyframes[keyframes.count - 1]
            return a.value.interpolated(to: b.value, progress: (time - a.time) / max(b.time - a.time, 1e-12), clamping: false)
        }
    }
    private func remappedTime(_ time: Double, first: Double, last: Double) -> Double {
        guard last > first else { return first }; if time >= first && time <= last { return time }
        let mode = time < first ? preExtrapolation : postExtrapolation, duration = last - first
        switch mode {
        case .clamp, .linear: return time
        case .cycle:
            var offset = (time - first).truncatingRemainder(dividingBy: duration); if offset < 0 { offset += duration }; return first + offset
        case .pingPong:
            let period = duration * 2; var offset = (time - first).truncatingRemainder(dividingBy: period); if offset < 0 { offset += period }
            return offset <= duration ? first + offset : last - (offset - duration)
        }
    }
    private func easingProgress(_ t: Double, mode: InterpolationMode, lower: Keyframe, upper: Keyframe) -> Double {
        switch mode {
        case .hold: return 0
        case .linear: return t
        case .autoBezier: return t * t * (3 - 2 * t)
        case .bezier:
            let c1 = min(max(0.3333333333 + lower.outHandle.valueOffset, -2), 3), c2 = min(max(0.6666666667 + upper.inHandle.valueOffset, -2), 3)
            return cubicBezier(t: t, p0: 0, p1: c1, p2: c2, p3: 1)
        case .back:
            let overshoot = 1.70158, x = t - 1; return 1 + (overshoot + 1) * x * x * x + overshoot * x * x
        case .bounce: return bounceOut(t)
        case .elastic:
            guard t > 0, t < 1 else { return t }; return pow(2, -10 * t) * sin((t * 10 - 0.75) * (2 * Double.pi / 3)) + 1
        }
    }
    private func cubicBezier(t: Double, p0: Double, p1: Double, p2: Double, p3: Double) -> Double {
        let u = 1 - t; return u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
    }
    private func bounceOut(_ t: Double) -> Double {
        let n = 7.5625, d = 2.75
        if t < 1 / d { return n * t * t }
        if t < 2 / d { let x = t - 1.5 / d; return n * x * x + 0.75 }
        if t < 2.5 / d { let x = t - 2.25 / d; return n * x * x + 0.9375 }
        let x = t - 2.625 / d; return n * x * x + 0.984375
    }
    private static func normalized(_ keyframes: [Keyframe]) -> [Keyframe] {
        let sorted = keyframes.sorted { $0.time == $1.time ? $0.id.uuidString < $1.id.uuidString : $0.time < $1.time }
        var result: [Keyframe] = []
        for keyframe in sorted where keyframe.time.isFinite {
            if let last = result.last, abs(last.time - keyframe.time) <= 1e-9 { result[result.count - 1] = keyframe } else { result.append(keyframe) }
        }
        return result
    }
}

public struct AnimatableProperty: Identifiable, Equatable, Codable, Sendable {
    public var id: PropertyID
    public var displayName: String
    public var defaultValue: KeyframeValue
    public var curve: AnimationKeyframeCurve
    public var isEnabled: Bool
    public init(id: PropertyID, displayName: String, defaultValue: KeyframeValue, curve: AnimationKeyframeCurve = .init(), isEnabled: Bool = true) {
        self.id = id; self.displayName = displayName; self.defaultValue = defaultValue; self.curve = curve; self.isEnabled = isEnabled
    }
    public func value(at time: Double) -> KeyframeValue { isEnabled ? curve.value(at: time, fallback: defaultValue) : defaultValue }
}

public struct TimeMapping: Equatable, Codable, Sendable {
    public var sourceDuration: Double
    public var outputDuration: Double
    public var curve: AnimationKeyframeCurve
    public init(sourceDuration: Double, outputDuration: Double, curve: AnimationKeyframeCurve) { self.sourceDuration = max(sourceDuration, 0); self.outputDuration = max(outputDuration, 0); self.curve = curve }
    public func sourceTime(at outputTime: Double) -> Double {
        let fallback = KeyframeValue.scalar(min(max(outputTime, 0), sourceDuration))
        guard case let .scalar(value) = curve.value(at: outputTime, fallback: fallback) else { return min(max(outputTime, 0), sourceDuration) }
        return min(max(value, 0), sourceDuration)
    }
}

public struct PropertyBinding: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var source: PropertyID
    public var target: PropertyID
    public var scale: Double
    public var offset: KeyframeValue?
    public var clamp: ClosedRange<Double>?
    public init(id: UUID = UUID(), source: PropertyID, target: PropertyID, scale: Double = 1, offset: KeyframeValue? = nil, clamp: ClosedRange<Double>? = nil) {
        self.id = id; self.source = source; self.target = target; self.scale = scale; self.offset = offset; self.clamp = clamp
    }
    public func transform(_ value: KeyframeValue) -> KeyframeValue {
        var result = value.scaled(by: scale); if let offset, let added = result.adding(offset) { result = added }
        if let clamp, case let .scalar(number) = result { result = .scalar(min(max(number, clamp.lowerBound), clamp.upperBound)) }
        return result
    }
}

public struct AnimationPreset: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var schemaVersion: Int
    public var properties: [AnimatableProperty]
    public var bindings: [PropertyBinding]
    public var metadata: [String: String]
    public init(id: UUID = UUID(), name: String, schemaVersion: Int = 1, properties: [AnimatableProperty], bindings: [PropertyBinding] = [], metadata: [String: String] = [:]) {
        self.id = id; self.name = name; self.schemaVersion = schemaVersion; self.properties = properties; self.bindings = bindings; self.metadata = metadata
    }
}
