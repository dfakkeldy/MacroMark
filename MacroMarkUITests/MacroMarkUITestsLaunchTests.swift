//
//  MacroMarkUITestsLaunchTests.swift
//  MacroMarkUITests
//
//  Created by Dan Fakkeldy on 2026-06-02.
//

import XCTest

final class MacroMarkUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.configureForIsolatedMacroMarkLaunch()
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["inbox.screen"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
