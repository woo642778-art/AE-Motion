import Foundation

public enum BPMFrameCalculator {
    public static func framesPerBeat(bpm: Double, fps: Double) -> Double {
        guard bpm > 0, fps > 0 else { return 0 }
        return 60 * fps / bpm
    }
    public static func frame(forBeat beat: Double, bpm: Double, fps: Double) -> Int {
        Int((beat * framesPerBeat(bpm: bpm, fps: fps)).rounded())
    }
}

public enum EasingCurveGenerator {
    public static func easeInOutCubic(samples: Int, durationFrames: Int) -> [KeyframePoint] {
        guard samples >= 2, durationFrames >= 1 else { return [] }
        return (0..<samples).map { index in
            let t = Double(index) / Double(samples - 1)
            let value = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            return KeyframePoint(frame: Int((t * Double(durationFrames)).rounded()), value: value)
        }
    }
}

public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public enum RandomValueGenerator {
    public static func values(count: Int, range: ClosedRange<Double>, seed: UInt64) -> [Double] {
        guard count > 0, range.lowerBound <= range.upperBound else { return [] }
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { _ in Double.random(in: range, using: &rng) }
    }
}

public enum LayerOffsetPlanner {
    public static func startFrames(layerCount: Int, firstFrame: Int, offsetFrames: Int) -> [Int] {
        guard layerCount > 0 else { return [] }
        return (0..<layerCount).map { firstFrame + $0 * offsetFrames }
    }
}

public enum CameraShakeGenerator {
    public static func samples(count: Int, amplitude: Double, decay: Double, seed: UInt64) -> [(x: Double, y: Double, rotation: Double)] {
        guard count > 0 else { return [] }
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { i in
            let falloff = pow(max(0, min(1, decay)), Double(i))
            return (
                Double.random(in: -amplitude...amplitude, using: &rng) * falloff,
                Double.random(in: -amplitude...amplitude, using: &rng) * falloff,
                Double.random(in: -(amplitude * 0.08)...(amplitude * 0.08), using: &rng) * falloff
            )
        }
    }
}

public enum ColorPaletteGenerator {
    public static func analogous(hue: Double, saturation: Double = 0.75, lightness: Double = 0.55) -> [RGBAColor] {
        [-30.0, -15.0, 0.0, 15.0, 30.0].map { hslToRGB(h: hue + $0, s: saturation, l: lightness) }
    }
    private static func hslToRGB(h: Double, s: Double, l: Double) -> RGBAColor {
        let hh = ((h.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 360
        let ss = max(0, min(1, s)), ll = max(0, min(1, l))
        if ss == 0 { return RGBAColor(red: ll, green: ll, blue: ll) }
        let q = ll < 0.5 ? ll * (1 + ss) : ll + ss - ll * ss
        let p = 2 * ll - q
        func channel(_ t0: Double) -> Double {
            var t = t0; if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            if t < 1/6 { return p + (q-p)*6*t }; if t < 1/2 { return q }; if t < 2/3 { return p + (q-p)*(2/3-t)*6 }; return p
        }
        return RGBAColor(red: channel(hh+1/3), green: channel(hh), blue: channel(hh-1/3))
    }
}

public enum ExpressionHelper {
    public static let snippets: [String: String] = [
        "overshoot": "value + sin(progress * pi) * amount",
        "loop": "progress - floor(progress)",
        "pingPong": "1 - abs(2 * fract(progress) - 1)",
        "damped": "1 - exp(-damping * t) * cos(frequency * t)",
    ]
}

public enum PresetCatalog {
    public static let textPresets = ["Fade Up", "Tracking Reveal", "Elastic Pop", "Word Cascade", "Typewriter"]
    public static let motionPresets = ["Smooth Push", "Impact Zoom", "Orbit Reveal", "Elastic Overshoot", "Handheld Drift"]
}
