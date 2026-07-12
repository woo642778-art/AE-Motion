import XCTest
@testable import AEMotionExtensionsCore

final class CoreTests: XCTestCase {
    func testCategoryInsertedAfterMoveTransform() {
        let input = [HostCategory(id: "color", title: "Color"), HostCategory(id: "move_transform", title: "Move & Transform"), HostCategory(id: "blur", title: "Blur")]
        XCTAssertEqual(CategoryInjector.insertExtensionsCategory(in: input).map(\.id), ["color", "move_transform", "com.aemotion.extensions", "blur"])
    }
    func testCategoryInsertedOnlyOnce() {
        let once = CategoryInjector.insertExtensionsCategory(in: [HostCategory(id: "moveTransform", title: "Move & Transform")])
        XCTAssertEqual(CategoryInjector.insertExtensionsCategory(in: once), once)
    }
    func testFramesPerBeat() { XCTAssertEqual(BPMFrameCalculator.framesPerBeat(bpm: 120, fps: 60), 30, accuracy: 0.0001) }
    func testEasingEndpoints() {
        let values = EasingCurveGenerator.easeInOutCubic(samples: 5, durationFrames: 60)
        XCTAssertEqual(values.first?.value, 0); XCTAssertEqual(values.last?.value, 1); XCTAssertEqual(values.last?.frame, 60)
    }
    func testRandomIsDeterministic() {
        XCTAssertEqual(RandomValueGenerator.values(count: 4, range: -1...1, seed: 7), RandomValueGenerator.values(count: 4, range: -1...1, seed: 7))
    }
    func testOffsetPlanner() { XCTAssertEqual(LayerOffsetPlanner.startFrames(layerCount: 4, firstFrame: 10, offsetFrames: 3), [10,13,16,19]) }
    func testCameraShakeDeterministic() {
        let a = CameraShakeGenerator.samples(count: 3, amplitude: 10, decay: 0.8, seed: 9)
        let b = CameraShakeGenerator.samples(count: 3, amplitude: 10, decay: 0.8, seed: 9)
        XCTAssertEqual(a.map(\.x), b.map(\.x)); XCTAssertEqual(a.map(\.y), b.map(\.y))
    }
    func testToolRegistryContainsFunctionalTools() {
        XCTAssertEqual(ToolRegistry.all.count, 14)
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "speed.remap" })
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "host.diagnostics" })
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "cutout.person" })
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "dead.frames" })
        XCTAssertTrue(ToolRegistry.all.contains { $0.id == "depth.map" })
    }
    func testConstantSpeedCurve() throws {
        let curve = try SpeedCurve.constant(duration: 3, velocity: 2)
        XCTAssertEqual(curve.velocity(at: 1.5), 2, accuracy: 1e-9)
        XCTAssertEqual(curve.sourceTime(at: 1.5), 3, accuracy: 1e-6)
    }
    func testReverseSpeedCurve() throws {
        let curve = try SpeedCurve.reverse(sourceDuration: 5)
        XCTAssertEqual(curve.sourceTime(at: 0), 5, accuracy: 1e-9)
        XCTAssertEqual(curve.sourceTime(at: 2), 3, accuracy: 1e-6)
        XCTAssertEqual(curve.sourceTime(at: 5), 0, accuracy: 1e-6)
    }
    func testFreezeSpeedCurve() throws {
        let curve = try SpeedCurve.constant(duration: 2, velocity: 0, sourceOrigin: 1.25)
        XCTAssertEqual(curve.sourceTime(at: 1.8), 1.25, accuracy: 1e-9)
    }
}
