import XCTest
@testable import AEMotionExtensionsCore

final class SafeToolRegistryTests: XCTestCase {
    func testSnapshotContainsOnlyIndependentUtilities() {
        let snapshot = SafeToolRegistry.snapshot()
        let ids = Set(snapshot.map(\.id))
        XCTAssertEqual(ids, SafeToolRegistry.independentToolIDs)
        XCTAssertFalse(ids.contains("speed.remap"))
        XCTAssertFalse(ids.contains("easing.curve"))
        XCTAssertFalse(ids.contains("cutout.person"))
        XCTAssertFalse(ids.contains("depth.map"))
        XCTAssertFalse(ids.contains("dead.frames"))
    }

    func testUnavailableReasonIsAttachedToOneRowOnly() {
        let snapshot = SafeToolRegistry.snapshot(
            unavailableReasons: ["resource.hub": "Required browser service is unavailable."]
        )
        let resource = snapshot.first { $0.id == "resource.hub" }
        let preset = snapshot.first { $0.id == "preset.library" }
        XCTAssertEqual(
            resource?.availability,
            .unavailable(reason: "Required browser service is unavailable.")
        )
        XCTAssertEqual(preset?.availability, .available)
    }

    func testSnapshotOrderMatchesToolRegistryOrder() {
        let expected = ToolRegistry.all
            .filter { SafeToolRegistry.independentToolIDs.contains($0.id) }
            .map(\.id)
        XCTAssertEqual(SafeToolRegistry.snapshot().map(\.id), expected)
    }
}
