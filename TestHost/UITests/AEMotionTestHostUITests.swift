import XCTest

final class AEMotionTestHostUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    func testExtensionsHubOpensWithoutCrash() throws {
        let readyLabel = app.staticTexts["testhost.ready"]
        XCTAssertTrue(
            readyLabel.waitForExistence(timeout: 15),
            "The Simulator test host did not finish launching."
        )

        let openButton = app.buttons["testhost.openExtensions"]
        XCTAssertTrue(
            openButton.waitForExistence(timeout: 5),
            "The Extensions & Scripts launch button is missing."
        )
        openButton.tap()

        XCTAssertTrue(
            app.navigationBars["Extensions & Scripts"].waitForExistence(timeout: 10),
            "Extensions & Scripts did not open or the process crashed during presentation."
        )

        XCTAssertTrue(
            app.searchFields["Search AE Motion tools"].waitForExistence(timeout: 5),
            "The Extensions hub search field is missing."
        )
    }
}
