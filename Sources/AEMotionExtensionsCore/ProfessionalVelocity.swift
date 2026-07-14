import Foundation

public enum FrameInterpolationMode: String, CaseIterable, Codable, Sendable { case nearest, frameBlend, opticalFlow }
public enum VelocityAudioMode: String, CaseIterable, Codable, Sendable { case linked, detached, pitchPreserved, muted }

public struct VelocityKeyframe: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var time: Double
    public var speed: Double
    public var interpolation: InterpolationMode
    public init(id: UUID = UUID(), time: Double, speed: Double, interpolation: InterpolationMode = .linear) { self.id = id; self.time = time; self.speed = speed; self.interpolation = interpolation }
}

public struct VelocityCurve: Equatable, Codable, Sendable {
    public private(set) var keyframes: [VelocityKeyframe]
    public var sourceOrigin: Double
    public init(keyframes: [VelocityKeyframe], sourceOrigin: Double = 0) { self.keyframes = Self.normalized(keyframes); self.sourceOrigin = sourceOrigin }
    public static func constant(duration: Double, speed: Double, sourceOrigin: Double = 0) -> VelocityCurve {
        VelocityCurve(keyframes: [VelocityKeyframe(time: 0, speed: speed), VelocityKeyframe(time: max(duration, 0), speed: speed)], sourceOrigin: sourceOrigin)
    }
    public mutating func replaceKeyframes(_ keyframes: [VelocityKeyframe]) { self.keyframes = Self.normalized(keyframes) }
    public func speed(at time: Double) -> Double {
        guard let first = keyframes.first else { return 1 }
        guard keyframes.count > 1, let last = keyframes.last else { return first.speed }
        if time <= first.time { return first.speed }; if time >= last.time { return last.speed }
        guard let upperIndex = keyframes.firstIndex(where: { $0.time >= time }), upperIndex > 0 else { return last.speed }
        let lower = keyframes[upperIndex - 1], upper = keyframes[upperIndex]
        if lower.interpolation == .hold { return lower.speed }
        let t = (time - lower.time) / max(upper.time - lower.time, 1e-12)
        let eased: Double
        switch lower.interpolation {
        case .autoBezier, .bezier: eased = t * t * (3 - 2 * t)
        case .back: let x = t - 1; eased = 1 + 2.70158 * x * x * x + 1.70158 * x * x
        case .bounce: eased = min(max(t + sin(t * .pi * 4) * (1 - t) * 0.15, 0), 1)
        case .elastic: eased = t == 0 || t == 1 ? t : pow(2, -10 * t) * sin((t * 10 - 0.75) * (2 * .pi / 3)) + 1
        case .hold: eased = 0
        case .linear: eased = t
        }
        return lower.speed + (upper.speed - lower.speed) * eased
    }
    public func sourceTime(at outputTime: Double, integrationStep: Double = 1.0 / 240.0) -> Double {
        guard outputTime > 0 else { return sourceOrigin }
        let step = max(min(integrationStep, outputTime), 1.0 / 2000.0)
        var time = 0.0, accumulated = sourceOrigin
        while time < outputTime { let next = min(time + step, outputTime); accumulated += speed(at: (time + next) * 0.5) * (next - time); time = next }
        return accumulated
    }
    public func timeMapping(outputDuration: Double, sourceDuration: Double, sampleRate: Double = 60) -> TimeMapping {
        let interval = 1 / max(sampleRate, 1); var frames: [Keyframe] = []; var time = 0.0
        while time < outputDuration { frames.append(Keyframe(time: time, value: .scalar(min(max(sourceTime(at: time), 0), sourceDuration)), interpolation: .linear)); time += interval }
        frames.append(Keyframe(time: outputDuration, value: .scalar(min(max(sourceTime(at: outputDuration), 0), sourceDuration)), interpolation: .linear))
        return TimeMapping(sourceDuration: sourceDuration, outputDuration: outputDuration, curve: AnimationKeyframeCurve(keyframes: frames))
    }
    private static func normalized(_ keyframes: [VelocityKeyframe]) -> [VelocityKeyframe] {
        let valid = keyframes.filter { $0.time.isFinite && $0.speed.isFinite }.sorted { $0.time < $1.time }; var result: [VelocityKeyframe] = []
        for keyframe in valid { if let last = result.last, abs(last.time - keyframe.time) <= 1e-9 { result[result.count - 1] = keyframe } else { result.append(keyframe) } }
        return result
    }
}

public struct VelocityMarker: Identifiable, Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case speedChange, beat, freeze, reverse, sceneReset }
    public var id: UUID
    public var time: Double
    public var kind: Kind
    public var label: String
    public init(id: UUID = UUID(), time: Double, kind: Kind, label: String) { self.id = id; self.time = time; self.kind = kind; self.label = label }
}

public struct ProfessionalVelocityPlan: Equatable, Codable, Sendable {
    public var curve: VelocityCurve
    public var frameInterpolation: FrameInterpolationMode
    public var audioMode: VelocityAudioMode
    public var bpm: Double?
    public var flowResetTimes: [Double]
    public init(curve: VelocityCurve, frameInterpolation: FrameInterpolationMode = .frameBlend, audioMode: VelocityAudioMode = .pitchPreserved, bpm: Double? = nil, flowResetTimes: [Double] = []) {
        self.curve = curve; self.frameInterpolation = frameInterpolation; self.audioMode = audioMode; self.bpm = bpm; self.flowResetTimes = flowResetTimes.filter(\.isFinite).sorted()
    }
    public static func ramp(duration: Double, from: Double, to: Double) -> ProfessionalVelocityPlan {
        ProfessionalVelocityPlan(curve: VelocityCurve(keyframes: [VelocityKeyframe(time: 0, speed: from, interpolation: .autoBezier), VelocityKeyframe(time: max(duration, 0), speed: to)]))
    }
    public static func freeze(duration: Double, sourceTime: Double) -> ProfessionalVelocityPlan {
        ProfessionalVelocityPlan(curve: .constant(duration: duration, speed: 0, sourceOrigin: sourceTime), frameInterpolation: .nearest, audioMode: .detached)
    }
    public static func reverse(duration: Double, sourceEnd: Double) -> ProfessionalVelocityPlan {
        ProfessionalVelocityPlan(curve: .constant(duration: duration, speed: -1, sourceOrigin: sourceEnd), frameInterpolation: .frameBlend, audioMode: .detached)
    }
    public func markers(outputDuration: Double) -> [VelocityMarker] {
        var result = curve.keyframes.dropFirst().dropLast().map { VelocityMarker(time: $0.time, kind: abs($0.speed) < 1e-9 ? .freeze : $0.speed < 0 ? .reverse : .speedChange, label: String(format: "%.2fx", $0.speed)) }
        if let bpm, bpm > 0 { let interval = 60 / bpm; var time = 0.0, beat = 1; while time <= outputDuration + 1e-9 { result.append(VelocityMarker(time: time, kind: .beat, label: "Beat \(beat)")); beat += 1; time += interval } }
        result.append(contentsOf: flowResetTimes.map { VelocityMarker(time: $0, kind: .sceneReset, label: "Flow Reset") })
        return result.sorted { $0.time < $1.time }
    }
}
