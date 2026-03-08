import XCTest

final class CueUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsMainWindowInUITestMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()

        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(window.staticTexts["Push to Talk"].waitForExistence(timeout: 10))
        XCTAssertTrue(window.staticTexts["Transcript"].exists)
        XCTAssertTrue(window.staticTexts["Latency"].exists)
    }
}
