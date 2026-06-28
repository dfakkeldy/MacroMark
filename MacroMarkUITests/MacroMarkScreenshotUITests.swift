import XCTest

@MainActor
final class MacroMarkScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += [ScreenshotLaunchArgument.mode]
        app.launchEnvironment["MACROMARK_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["FASTLANE_SNAPSHOT"] = "1"
        app.launch()
    }

    func testAppStoreScreenshots() throws {
        let standupText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Standup")).firstMatch
        XCTAssertTrue(standupText.waitForExistence(timeout: 10))
        captureScreenshot(named: "01-inbox")

        let firstNote = app.buttons.matching(identifier: "note.row").firstMatch
        XCTAssertTrue(firstNote.waitForExistence(timeout: 5))
        firstNote.tap()
        XCTAssertTrue(app.navigationBars["Note Details"].waitForExistence(timeout: 5))
        captureScreenshot(named: "02-note-detail")

        switchToMacros()
        XCTAssertTrue(app.staticTexts["Standup"].waitForExistence(timeout: 5))
        captureScreenshot(named: "03-macros")

        app.buttons["Add"].tap()
        XCTAssertTrue(app.navigationBars["New Macro"].waitForExistence(timeout: 5))
        captureScreenshot(named: "04-new-macro")
    }

    private func captureScreenshot(named name: String) {
        snapshot(name, timeWaitingForIdle: 0)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func switchToMacros() {
        if tapControl(named: "Macros", timeout: 2) {
            return
        }

        let leadingNavigationButton = app.navigationBars.buttons.element(boundBy: 0)
        if leadingNavigationButton.exists {
            leadingNavigationButton.tap()
        }

        XCTAssertTrue(tapControl(named: "Macros", timeout: 5))
    }

    private func tapControl(named name: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@ OR identifier == %@", name, name)

        let tabBarButton = app.tabBars.buttons.matching(predicate).firstMatch
        if tabBarButton.waitForExistence(timeout: timeout) {
            tabBarButton.tap()
            return true
        }

        let button = app.buttons.matching(predicate).firstMatch
        if button.waitForExistence(timeout: timeout) {
            button.tap()
            return true
        }

        let cell = app.cells.matching(predicate).firstMatch
        if cell.waitForExistence(timeout: timeout) {
            cell.tap()
            return true
        }

        return false
    }
}

private enum ScreenshotLaunchArgument {
    static let mode = "--screenshot-mode"
}
