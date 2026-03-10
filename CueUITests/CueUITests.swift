import XCTest

final class CueUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchOpensCueWindowFromMenuBarMenu() throws {
        let app = XCUIApplication()
        let systemUI = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")

        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.activate()

        let menuBarItem = app
            .descendants(matching: .statusItem)
            .matching(identifier: CueAccessibilityID.menuBarTrigger)
            .firstMatch
        XCTAssertTrue(menuBarItem.waitForExistence(timeout: 15))

        let mainWindow = app.descendants(matching: .any)[CueAccessibilityID.mainWindowRoot]
        XCTAssertFalse(mainWindow.exists)

        openCueWindow(using: menuBarItem, app: app, systemUI: systemUI)

        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Push to Talk"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)[CueAccessibilityID.shortcutRecorder].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)[CueAccessibilityID.pushToTalkSection].exists)

        openCueWindow(using: menuBarItem, app: app, systemUI: systemUI)

        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: CueAccessibilityID.mainWindowRoot)
                .count,
            1
        )
    }

    private func openCueWindow(using menuBarItem: XCUIElement, app: XCUIApplication, systemUI: XCUIApplication) {
        for _ in 0..<3 {
            menuBarItem.click()

            if let openCueMenuItem = findOpenCueMenuItem(app: app, systemUI: systemUI, timeout: 3) {
                openCueMenuItem.click()
                return
            }
        }

        XCTFail("Failed to find the Open Cue menu item")
    }

    private func findOpenCueMenuItem(app: XCUIApplication, systemUI: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let candidates = [
            app.descendants(matching: .menuItem)[CueAccessibilityID.openCueMenuItem],
            systemUI.descendants(matching: .menuItem)[CueAccessibilityID.openCueMenuItem],
            app.menuItems["Open Cue"],
            systemUI.menuItems["Open Cue"],
        ]

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for candidate in candidates where candidate.exists {
                return candidate
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        while Date() < deadline

        return nil
    }
}
