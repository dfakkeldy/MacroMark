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
        // Preserve Fastlane's configured locale; use Canadian English for a
        // standalone local capture that has no Snapshot language/locale files.
        if !app.launchArguments.contains("-AppleLanguages") {
            app.launchArguments += ["-AppleLanguages", "(en)"]
        }
        if !app.launchArguments.contains("-AppleLocale") {
            app.launchArguments += ["-AppleLocale", "en_CA"]
        }
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
        let directSend = app.buttons["Direct Send"]
        XCTAssertTrue(directSend.waitForExistence(timeout: 5))
        directSend.tap()
        XCTAssertTrue(app.navigationBars["Direct Send"].waitForExistence(timeout: 5))
        let saveSetup = app.buttons["Save and send setup to watch"]
        XCTAssertTrue(saveSetup.waitForExistence(timeout: 5))
        XCTAssertTrue(saveSetup.isEnabled, "Screenshot fixture must load without a secure-settings error")
        XCTAssertFalse(app.staticTexts["Secure settings could not be read. Unlock your iPhone and reopen this screen."].exists)
        captureScreenshot(named: "05-direct-send")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(scrollToTextContaining("Capture Idea"))
        frameMacroList()
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

    private func frameMacroList() {
        let lastDescription = app.staticTexts["Inserts the capture location when location access is available."]
        XCTAssertTrue(lastDescription.waitForExistence(timeout: 5))
        let tabBar = app.tabBars.firstMatch
        // iPad tabs can be at the top; only bottom tabs obscure the list's end.
        let bottom = tabBar.exists && tabBar.frame.minY > app.frame.midY
            ? tabBar.frame.minY - 16 : app.frame.maxY - 32
        for _ in 0..<4 {
            let overflow = lastDescription.frame.maxY - bottom
            if overflow <= 0 { break }
            // A short drag avoids flinging the first custom macro offscreen.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7))
            let end = start.withOffset(CGVector(dx: 0, dy: -min(overflow + 20, 100)))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertLessThanOrEqual(lastDescription.frame.maxY, bottom)
        XCTAssertGreaterThan(app.staticTexts["Standup"].frame.minY, app.navigationBars.firstMatch.frame.maxY)
    }

    private func scrollToTextContaining(_ text: String, attempts: Int = 4) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let matchingText = app.staticTexts.matching(predicate).firstMatch

        for _ in 0...attempts {
            if matchingText.waitForExistence(timeout: 1), matchingText.isHittable,
               matchingText.frame.maxY < app.frame.maxY - 120 {
                return true
            }
            app.swipeUp()
        }

        return false
    }
}
