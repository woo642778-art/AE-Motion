import XCTest
@testable import AEMotionExtensionsCore

final class AEMotionRouteStateTests: XCTestCase {
    func testSelectingTabClosesCreateTrayAndClearsTransientRoutes() {
        var state = AEMotionRouteState(
            selectedTab: .home,
            modal: .createTray,
            nonRoot: nil,
            isCreateTrayPresented: true
        )

        AEMotionRouteReducer.reduce(state: &state, event: .selectTab(.projects))

        XCTAssertEqual(state.selectedTab, .projects)
        XCTAssertNil(state.modal)
        XCTAssertNil(state.nonRoot)
        XCTAssertFalse(state.isCreateTrayPresented)
    }

    func testCreateButtonTogglesTrayAndNeverCreatesASecondModal() {
        var state = AEMotionRouteState()

        AEMotionRouteReducer.reduce(state: &state, event: .toggleCreateTray)
        XCTAssertTrue(state.isCreateTrayPresented)
        XCTAssertEqual(state.modal, .createTray)

        AEMotionRouteReducer.reduce(state: &state, event: .toggleCreateTray)
        XCTAssertFalse(state.isCreateTrayPresented)
        XCTAssertNil(state.modal)
    }

    func testOutsideTapDismissesOnlyCreateTray() {
        var state = AEMotionRouteState(
            selectedTab: .templates,
            modal: .createTray,
            nonRoot: nil,
            isCreateTrayPresented: true
        )

        AEMotionRouteReducer.reduce(state: &state, event: .dismissCreateTray)

        XCTAssertEqual(state.selectedTab, .templates)
        XCTAssertFalse(state.isCreateTrayPresented)
        XCTAssertNil(state.modal)
    }

    func testOpeningModalClosesCreateTrayAndPreservesSelectedTab() {
        var state = AEMotionRouteState(
            selectedTab: .projects,
            modal: .createTray,
            nonRoot: nil,
            isCreateTrayPresented: true
        )

        AEMotionRouteReducer.reduce(state: &state, event: .presentModal(.settings))

        XCTAssertEqual(state.selectedTab, .projects)
        XCTAssertEqual(state.modal, .settings)
        XCTAssertNil(state.nonRoot)
        XCTAssertFalse(state.isCreateTrayPresented)
    }

    func testDismissingModalReturnsToExactPriorRootTab() {
        var state = AEMotionRouteState(
            selectedTab: .tutorials,
            modal: .account,
            nonRoot: nil,
            isCreateTrayPresented: false
        )

        AEMotionRouteReducer.reduce(state: &state, event: .dismissModal)

        XCTAssertEqual(state.selectedTab, .tutorials)
        XCTAssertNil(state.modal)
        XCTAssertNil(state.nonRoot)
    }

    func testConfirmedNonRootRouteClosesModalAndCreateTray() {
        var state = AEMotionRouteState(
            selectedTab: .home,
            modal: .createTray,
            nonRoot: nil,
            isCreateTrayPresented: true
        )

        AEMotionRouteReducer.reduce(state: &state, event: .confirmNonRoot(.threeDStudio))

        XCTAssertEqual(state.nonRoot, .threeDStudio)
        XCTAssertNil(state.modal)
        XCTAssertFalse(state.isCreateTrayPresented)
    }

    func testFailedRouteLeavesPreviousRootStateUnchanged() {
        let original = AEMotionRouteState(
            selectedTab: .templates,
            modal: nil,
            nonRoot: nil,
            isCreateTrayPresented: false
        )
        var state = original

        AEMotionRouteReducer.reduce(state: &state, event: .routeFailed)

        XCTAssertEqual(state, original)
    }

    func testReturningToRootClearsTransientState() {
        var state = AEMotionRouteState(
            selectedTab: .home,
            modal: nil,
            nonRoot: .projectEditor,
            isCreateTrayPresented: false
        )

        AEMotionRouteReducer.reduce(state: &state, event: .returnToRoot(.projects))

        XCTAssertEqual(state.selectedTab, .projects)
        XCTAssertNil(state.modal)
        XCTAssertNil(state.nonRoot)
        XCTAssertFalse(state.isCreateTrayPresented)
    }

    func testBackgroundAlwaysClosesCreateTray() {
        var state = AEMotionRouteState(
            selectedTab: .home,
            modal: .createTray,
            nonRoot: nil,
            isCreateTrayPresented: true
        )

        AEMotionRouteReducer.reduce(state: &state, event: .applicationDidEnterBackground)

        XCTAssertFalse(state.isCreateTrayPresented)
        XCTAssertNil(state.modal)
    }
}
