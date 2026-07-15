import XCTest
import AEMotionExtensionsHost

@MainActor
final class AEMotionTestHostTests: XCTestCase {
    func testToolRegistryIsExposedToTestHost() {
        XCTAssertGreaterThan(
            AEMotionTestHostBridge.registeredToolCount,
            0,
            "The Simulator host must expose at least one registered AE Motion tool."
        )
    }

    func testToolIdentifiersAreUnique() {
        let identifiers = AEMotionTestHostBridge.registeredToolIDs
        XCTAssertEqual(
            identifiers.count,
            Set(identifiers).count,
            "Duplicate tool identifiers make UI routing and regression tests ambiguous."
        )
    }
}
