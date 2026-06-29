import XCTest

@MainActor
final class MacroMarkScreenshotUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        setupSnapshot(app)
        app.configureForMacroMarkScreenshots()
        app.launch()
        XCUIDevice.shared.orientation = .portrait
    }

    func testAppStoreScreenshots() throws {
        XCTAssertTrue(scrollToTextContaining("Standup"))
        captureScreenshot(named: "01-inbox")

        let firstNote = app.buttons.matching(identifier: "note.row").firstMatch
        XCTAssertTrue(firstNote.waitForExistence(timeout: 5))
        firstNote.tap()
        XCTAssertTrue(app.descendants(matching: .any)["noteDetail.form"].waitForExistence(timeout: 5))
        captureScreenshot(named: "02-note-detail")

        switchToMacros()
        XCTAssertTrue(scrollToTextContaining("Standup"))
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

    private func scrollToTextContaining(_ text: String, attempts: Int = 4) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let matchingText = app.staticTexts.matching(predicate).firstMatch

        for _ in 0...attempts {
            if matchingText.waitForExistence(timeout: 1) {
                return true
            }
            app.swipeUp()
        }

        return false
    }
}
