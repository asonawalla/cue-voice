import XCTest

final class CueUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsMenuBarPopoverInUITestMode() throws {
        let app = XCUIApplication()
        let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")

        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()

        let menuBarItem = systemUI.menuBars.buttons["Ready"]
        XCTAssertTrue(menuBarItem.waitForExistence(timeout: 10))
        menuBarItem.click()

        let popover = app.descendants(matching: .any)[CueAccessibilityID.popoverRoot]
        XCTAssertTrue(popover.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Push to Talk"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)[CueAccessibilityID.pushToTalkSection].exists)
        XCTAssertTrue(app.descendants(matching: .any)[CueAccessibilityID.shortcutRecorder].exists)
        XCTAssertTrue(app.buttons["Quit Cue"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)[CueAccessibilityID.quitButton].exists)
    }
}
