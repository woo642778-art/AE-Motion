import XCTest
@testable import AEMotionExtensionsCore

final class HomeShellStateTests: XCTestCase {
    func testReleaseIdentity() {
        XCTAssertEqual(AEMotionRelease.marketingVersion, "2.7.2")
        XCTAssertEqual(AEMotionRelease.buildNumber, 845)
    }

    func testNonRootDestinationsHideNavigationAndReturnRestoresIt() {
        for destination in [
            HomeShellDestination.detail,
            .editor,
            .templatePreview,
            .tool,
        ] {
            var state = HomeShellState()
            HomeShellReducer.reduce(state: &state, event: .openDestination(destination))
            XCTAssertFalse(state.isRootNavigationVisible)
            HomeShellReducer.reduce(state: &state, event: .returnToRoot)
            XCTAssertTrue(state.isRootNavigationVisible)
        }
    }

    func testSelectingTabClosesCreateTrayWithoutChangingRootVisibility() {
        var state = HomeShellState(selectedTab: .home, isCreateTrayExpanded: true)
        HomeShellReducer.reduce(state: &state, event: .selectTab(.templates))
        XCTAssertEqual(state.selectedTab, .templates)
        XCTAssertFalse(state.isCreateTrayExpanded)
        XCTAssertTrue(state.isRootNavigationVisible)
    }

    func testCreateTrayCannotOpenOutsideRootDestination() {
        var state = HomeShellState(destination: .editor)
        HomeShellReducer.reduce(state: &state, event: .setCreateTrayExpanded(true))
        XCTAssertFalse(state.isCreateTrayExpanded)
        XCTAssertFalse(state.isRootNavigationVisible)
    }
}
