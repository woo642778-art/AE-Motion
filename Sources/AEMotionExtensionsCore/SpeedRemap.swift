import Foundation

public enum SpeedRemapError: Error, Equatable, Sendable {
    case tooFewKeyframes
    case nonIncreasingOutputTime
    case invalidNumber
    case invalidDuration
    case invalidFrameRate
}

public struct SpeedKeyframe: Equatable, Sendable, Codable, Identifiable {
    public let id: UUID
    public var outputTime: Double
    public var velocity: Double
    public var incomingSlope: Double?
    public var outgoingSlope: Double?

    public init(
        id: UUID = UUID(),
        outputTime: Double,
        velocity: Double,
        incomingSlope: Double? = nil,
        outgoingSlope: Double? = nil
    ) {
        self.id = id
        self.outputTime = outputTime
        self.velocity = velocity
        self.incomingSlope = incomingSlope
        self.outgoingSlope = outgoingSlope
    }
}

/// AE-style speed graph. Velocity is source-seconds per output-second:
/// 1 = normal, 2 = 2x, 0.5 = half speed, 0 = freeze, negative = reverse.
public struct SpeedCurve: Sendable {
    public let sourceOrigin: Double
    public let keyframes: [SpeedKeyframe]

    private let incomingSlopes: [Double]
    private let outgoingSlopes: [Double]
    private let cumulativeSourceOffsets: [Double]

    public init(sourceOrigin: Double, keyframes: [SpeedKeyframe]) throws {
        guard sourceOrigin.isFinite, keyframes.allSatisfy({ point in
            point.outputTime.isFinite && point.velocity.isFinite &&
            (point.incomingSlope?.isFinite ?? true) &&
            (point.outgoingSlope?.isFinite ?? true)
        }) else {
            throw SpeedRemapError.invalidNumber
        }
        guard keyframes.count >= 2 else { throw SpeedRemapError.tooFewKeyframes }

        let sorted = keyframes.sorted { $0.outputTime < $1.outputTime }
        for index in 1..<sorted.count where sorted[index].outputTime <= sorted[index - 1].outputTime {
            throw SpeedRemapError.nonIncreasingOutputTime
        }

        self.sourceOrigin = sourceOrigin
        self.keyframes = sorted

        var automatic = Array(repeating: 0.0, count: sorted.count)
        for index in sorted.indices {
            if index == sorted.startIndex {
                automatic[index] = Self.secant(sorted[index], sorted[index + 1])
            } else if index == sorted.index(before: sorted.endIndex) {
                automatic[index] = Self.secant(sorted[index - 1], sorted[index])
            } else {
                let left = Self.secant(sorted[index - 1], sorted[index])
                let right = Self.secant(sorted[index], sorted[index + 1])
                automatic[index] = (left + right) * 0.5
            }
        }

        incomingSlopes = sorted.indices.map { index in
            sorted[index].incomingSlope ?? automatic[index]
        }
        outgoingSlopes = sorted.indices.map { index in
            sorted[index].outgoingSlope ?? automatic[index]
        }

        var offsets = Array(repeating: 0.0, count: sorted.count)
        for index in 0..<(sorted.count - 1) {
            offsets[index + 1] = offsets[index] + Self.integral(
                from: sorted[index],
                to: sorted[index + 1],
                startSlope: outgoingSlopes[index],
                endSlope: incomingSlopes[index + 1],
                normalizedUpperBound: 1
            )
        }
        cumulativeSourceOffsets = offsets
    }

    public static func constant(
        duration: Double,
        velocity: Double,
        sourceOrigin: Double = 0
    ) throws -> SpeedCurve {
        guard duration.isFinite, duration > 0 else { throw SpeedRemapError.invalidDuration }
        return try SpeedCurve(
            sourceOrigin: sourceOrigin,
            keyframes: [
                SpeedKeyframe(outputTime: 0, velocity: velocity, incomingSlope: 0, outgoingSlope: 0),
                SpeedKeyframe(outputTime: duration, velocity: velocity, incomingSlope: 0, outgoingSlope: 0),
            ]
        )
    }

    public static func reverse(sourceDuration: Double) throws -> SpeedCurve {
        guard sourceDuration.isFinite, sourceDuration > 0 else {
            throw SpeedRemapError.invalidDuration
        }
        return try constant(duration: sourceDuration, velocity: -1, sourceOrigin: sourceDuration)
    }

    public var outputDuration: Double {
        (keyframes.last?.outputTime ?? 0) - (keyframes.first?.outputTime ?? 0)
    }

    public func velocity(at outputTime: Double) -> Double {
        if outputTime <= keyframes[0].outputTime { return keyframes[0].velocity }
        if outputTime >= keyframes.last!.outputTime { return keyframes.last!.velocity }

        let index = segmentIndex(for: outputTime)
        let start = keyframes[index]
        let end = keyframes[index + 1]
        let duration = end.outputTime - start.outputTime
        let u = (outputTime - start.outputTime) / duration
        return Self.hermite(
            startValue: start.velocity,
            endValue: end.velocity,
            startSlope: outgoingSlopes[index],
            endSlope: incomingSlopes[index + 1],
            duration: duration,
            u: u
        )
    }

    public func sourceTime(at outputTime: Double) -> Double {
        guard outputTime.isFinite else { return sourceOrigin }
        let first = keyframes[0]
        let last = keyframes[keyframes.count - 1]
        if outputTime <= first.outputTime {
            return sourceOrigin + (outputTime - first.outputTime) * first.velocity
        }
        if outputTime >= last.outputTime {
            return sourceOrigin + cumulativeSourceOffsets.last! +
                (outputTime - last.outputTime) * last.velocity
        }

        let index = segmentIndex(for: outputTime)
        let start = keyframes[index]
        let end = keyframes[index + 1]
        let u = (outputTime - start.outputTime) / (end.outputTime - start.outputTime)
        let partial = Self.integral(
            from: start,
            to: end,
            startSlope: outgoingSlopes[index],
            endSlope: incomingSlopes[index + 1],
            normalizedUpperBound: u
        )
        return sourceOrigin + cumulativeSourceOffsets[index] + partial
    }

    public func sampledVelocity(count: Int) -> [KeyframePoint] {
        guard count >= 2 else { return [] }
        let start = keyframes.first!.outputTime
        let duration = outputDuration
        return (0..<count).map { index in
            let p = Double(index) / Double(count - 1)
            let time = start + p * duration
            return KeyframePoint(frame: index, value: velocity(at: time))
        }
    }

    private func segmentIndex(for outputTime: Double) -> Int {
        var low = 0
        var high = keyframes.count - 1
        while low + 1 < high {
            let middle = (low + high) / 2
            if keyframes[middle].outputTime <= outputTime {
                low = middle
            } else {
                high = middle
            }
        }
        return low
    }

    private static func secant(_ a: SpeedKeyframe, _ b: SpeedKeyframe) -> Double {
        (b.velocity - a.velocity) / (b.outputTime - a.outputTime)
    }

    private static func hermite(
        startValue: Double,
        endValue: Double,
        startSlope: Double,
        endSlope: Double,
        duration: Double,
        u: Double
    ) -> Double {
        let u2 = u * u
        let u3 = u2 * u
        let h00 = 2 * u3 - 3 * u2 + 1
        let h10 = u3 - 2 * u2 + u
        let h01 = -2 * u3 + 3 * u2
        let h11 = u3 - u2
        return h00 * startValue + h10 * duration * startSlope +
            h01 * endValue + h11 * duration * endSlope
    }

    private static func integral(
        from start: SpeedKeyframe,
        to end: SpeedKeyframe,
        startSlope: Double,
        endSlope: Double,
        normalizedUpperBound u: Double
    ) -> Double {
        let duration = end.outputTime - start.outputTime
        let u2 = u * u
        let u3 = u2 * u
        let u4 = u3 * u
        let i00 = 0.5 * u4 - u3 + u
        let i10 = 0.25 * u4 - (2.0 / 3.0) * u3 + 0.5 * u2
        let i01 = -0.5 * u4 + u3
        let i11 = 0.25 * u4 - (1.0 / 3.0) * u3
        return duration * (
            i00 * start.velocity +
            i10 * duration * startSlope +
            i01 * end.velocity +
            i11 * duration * endSlope
        )
    }
}

public struct SpeedFrameSample: Equatable, Sendable {
    public let outputTime: Double
    public let sourceTime: Double

    public init(outputTime: Double, sourceTime: Double) {
        self.outputTime = outputTime
        self.sourceTime = sourceTime
    }
}

public enum SpeedFrameSamplePlanner {
    public static func plan(
        curve: SpeedCurve,
        outputDuration: Double,
        frameRate: Double
    ) throws -> [SpeedFrameSample] {
        guard outputDuration.isFinite, outputDuration >= 0 else {
            throw SpeedRemapError.invalidDuration
        }
        guard frameRate.isFinite, frameRate > 0 else {
            throw SpeedRemapError.invalidFrameRate
        }

        let frameCount = Int((outputDuration * frameRate).rounded(.down))
        var result = (0...frameCount).map { frame -> SpeedFrameSample in
            let outputTime = min(Double(frame) / frameRate, outputDuration)
            return SpeedFrameSample(
                outputTime: outputTime,
                sourceTime: curve.sourceTime(at: outputTime)
            )
        }
        if result.last?.outputTime != outputDuration {
            result.append(SpeedFrameSample(
                outputTime: outputDuration,
                sourceTime: curve.sourceTime(at: outputDuration)
            ))
        }
        return result
    }
}

public enum SpeedRemapPreset {
    public static func smoothRamp(duration: Double) -> [SpeedKeyframe] {
        [
            .init(outputTime: 0, velocity: 0.25, outgoingSlope: 1.4),
            .init(outputTime: duration * 0.35, velocity: 2.5, incomingSlope: 0, outgoingSlope: 0),
            .init(outputTime: duration * 0.65, velocity: 2.5, incomingSlope: 0, outgoingSlope: -1.4),
            .init(outputTime: duration, velocity: 0.25, incomingSlope: 0),
        ]
    }

    public static func impact(duration: Double) -> [SpeedKeyframe] {
        [
            .init(outputTime: 0, velocity: 1, outgoingSlope: -4),
            .init(outputTime: duration * 0.28, velocity: 0.08, incomingSlope: 0, outgoingSlope: 7),
            .init(outputTime: duration * 0.45, velocity: 3.5, incomingSlope: 0, outgoingSlope: -2),
            .init(outputTime: duration, velocity: 1, incomingSlope: 0),
        ]
    }

    public static func freezeHit(duration: Double) -> [SpeedKeyframe] {
        [
            .init(outputTime: 0, velocity: 1, outgoingSlope: 0),
            .init(outputTime: duration * 0.35, velocity: 1, incomingSlope: 0, outgoingSlope: -6),
            .init(outputTime: duration * 0.45, velocity: 0, incomingSlope: 0, outgoingSlope: 0),
            .init(outputTime: duration * 0.65, velocity: 0, incomingSlope: 0, outgoingSlope: 6),
            .init(outputTime: duration * 0.75, velocity: 1, incomingSlope: 0, outgoingSlope: 0),
            .init(outputTime: duration, velocity: 1, incomingSlope: 0),
        ]
    }
}
