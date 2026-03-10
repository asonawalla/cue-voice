import XCTest

final class CueUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsMenuBarPopoverInUITestMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()

        let menuBarItem = app
            .descendants(matching: .statusItem)
            .matching(identifier: CueAccessibilityID.menuBarTrigger)
            .firstMatch
        XCTAssertTrue(menuBarItem.waitForExistence(timeout: 15))

        let popover = app.descendants(matching: .any)[CueAccessibilityID.popoverRoot]
        openMenuBarPopover(using: menuBarItem, popover: popover)

        XCTAssertTrue(app.staticTexts["Push to Talk"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)[CueAccessibilityID.shortcutRecorder].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Quit Cue"].waitForExistence(timeout: 10))
    }

    private func openMenuBarPopover(using menuBarItem: XCUIElement, popover: XCUIElement) {
        if popover.exists {
            return
        }

        for _ in 0..<3 {
            menuBarItem.click()
            if popover.waitForExistence(timeout: 3) {
                return
            }
        }

        XCTAssertTrue(popover.waitForExistence(timeout: 3))
    }
}
