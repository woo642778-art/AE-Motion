import XCTest
@testable import AEMotionExtensionsCore

final class AnimationCoreTests: XCTestCase {
    func testLinearCurveEvaluationAndSpeed() {
        let curve = AnimationKeyframeCurve(keyframes: [Keyframe(time: 0, value: .scalar(0), interpolation: .linear), Keyframe(time: 2, value: .scalar(10), interpolation: .linear)])
        XCTAssertEqual(curve.value(at: 1, fallback: .scalar(0)), .scalar(5)); XCTAssertEqual(curve.speed(at: 1, fallback: .scalar(0)), 5, accuracy: 0.02)
    }
    func testHoldCurveKeepsPreviousValue() {
        let curve = AnimationKeyframeCurve(keyframes: [Keyframe(time: 0, value: .scalar(2), interpolation: .hold), Keyframe(time: 1, value: .scalar(8), interpolation: .linear)])
        XCTAssertEqual(curve.value(at: 0.75, fallback: .scalar(0)), .scalar(2)); XCTAssertEqual(curve.value(at: 1, fallback: .scalar(0)), .scalar(8))
    }
    func testCycleAndPingPongExtrapolation() {
        let cycle = AnimationKeyframeCurve(keyframes: [Keyframe(time: 0, value: .scalar(0), interpolation: .linear), Keyframe(time: 1, value: .scalar(1), interpolation: .linear)], preExtrapolation: .cycle, postExtrapolation: .cycle)
        XCTAssertEqual(cycle.value(at: 1.25, fallback: .scalar(0)), .scalar(0.25))
        let pingPong = AnimationKeyframeCurve(keyframes: cycle.keyframes, preExtrapolation: .pingPong, postExtrapolation: .pingPong)
        XCTAssertEqual(pingPong.value(at: 1.25, fallback: .scalar(0)), .scalar(0.75))
    }
    func testLinearExtrapolationIsNotClamped() {
        let curve = AnimationKeyframeCurve(keyframes: [Keyframe(time: 0, value: .scalar(0), interpolation: .linear), Keyframe(time: 1, value: .scalar(2), interpolation: .linear)], preExtrapolation: .linear, postExtrapolation: .linear)
        XCTAssertEqual(curve.value(at: 2, fallback: .scalar(0)), .scalar(4))
    }
    func testAngleInterpolationUsesShortestPath() { XCTAssertEqual(KeyframeValue.angle(350).interpolated(to: .angle(10), progress: 0.5), .angle(360)) }
    func testPropertyBindingTransformsScalar() {
        let binding = PropertyBinding(source: "audio.low", target: "glow.strength", scale: 2, offset: .scalar(1), clamp: 0...3)
        XCTAssertEqual(binding.transform(.scalar(2)), .scalar(3))
    }
    func testAnimationPresetRoundTrip() throws {
        let preset = AnimationPreset(name: "Overshoot", properties: [AnimatableProperty(id: "transform.scale", displayName: "Scale", defaultValue: .scalar(1), curve: AnimationKeyframeCurve(keyframes: [Keyframe(time: 0, value: .scalar(0.8), interpolation: .back), Keyframe(time: 1, value: .scalar(1), interpolation: .autoBezier)]))])
        let data = try JSONEncoder().encode(preset); XCTAssertEqual(try JSONDecoder().decode(AnimationPreset.self, from: data), preset)
    }
    func testMotionCleanupReducesNoisyPathAndPreservesEndpoints() {
        let samples = (0...100).map { GestureSample(time: Double($0) / 60, x: Double($0), y: sin(Double($0) * 0.1) * 0.15) }
        let cleaned = MotionCleanup.cleaned(samples, smoothingRadius: 2, simplificationTolerance: 0.4)
        XCTAssertLessThan(cleaned.count, samples.count); XCTAssertEqual(cleaned.first?.x, samples.first?.x); XCTAssertEqual(cleaned.last?.x, samples.last?.x); XCTAssertEqual(cleaned.first?.time, 0)
    }
    func testGestureRecorderSamplesAndBuildsThreeProperties() {
        var recorder = GestureRecorder(minimumSampleInterval: 1.0 / 60.0)
        recorder.append(.init(time: 0, x: 0, y: 0)); recorder.append(.init(time: 0.001, x: 1, y: 1, rotation: 1, scale: 1.01)); recorder.append(.init(time: 1.0 / 30.0, x: 10, y: 20, rotation: 20, scale: 1.2))
        XCTAssertEqual(recorder.sampleCount, 2); let recording = recorder.finish(cleanup: false); XCTAssertEqual(recording.position.curve.keyframes.count, 2); XCTAssertEqual(recording.rotation.curve.keyframes.count, 2); XCTAssertEqual(recording.scale.curve.keyframes.count, 2)
    }
    func testVelocityConstantForwardReverseAndFreeze() {
        XCTAssertEqual(VelocityCurve.constant(duration: 3, speed: 2).sourceTime(at: 1.5), 3, accuracy: 0.01)
        XCTAssertEqual(ProfessionalVelocityPlan.reverse(duration: 3, sourceEnd: 5).curve.sourceTime(at: 2), 3, accuracy: 0.01)
        XCTAssertEqual(ProfessionalVelocityPlan.freeze(duration: 3, sourceTime: 1.25).curve.sourceTime(at: 2.5), 1.25, accuracy: 0.001)
    }
    func testVelocityRampAndBPMMarkers() {
        var plan = ProfessionalVelocityPlan.ramp(duration: 2, from: 0.5, to: 2); plan.bpm = 120
        XCTAssertEqual(plan.curve.speed(at: 0), 0.5, accuracy: 0.001); XCTAssertEqual(plan.curve.speed(at: 2), 2, accuracy: 0.001)
        XCTAssertEqual(plan.markers(outputDuration: 2).filter { $0.kind == .beat }.map(\.time), [0, 0.5, 1, 1.5, 2])
    }
    func testTimeMappingClampsToSourceDuration() {
        let curve = AnimationKeyframeCurve(keyframes: [Keyframe(time: 0, value: .scalar(-1), interpolation: .linear), Keyframe(time: 1, value: .scalar(9), interpolation: .linear)])
        let mapping = TimeMapping(sourceDuration: 4, outputDuration: 1, curve: curve); XCTAssertEqual(mapping.sourceTime(at: 0), 0); XCTAssertEqual(mapping.sourceTime(at: 1), 4)
    }
}
