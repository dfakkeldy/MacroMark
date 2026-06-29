import XCTest

extension XCUIApplication {
    @MainActor
    func configureForIsolatedMacroMarkLaunch() {
        launchArguments += ["--ui-test-mode"]
        launchEnvironment["MACROMARK_UI_TEST_MODE"] = "1"
    }

    @MainActor
    func configureForMacroMarkScreenshots() {
        configureForIsolatedMacroMarkLaunch()
        launchArguments += ["--screenshot-mode"]
        launchEnvironment["MACROMARK_SCREENSHOT_MODE"] = "1"
        launchEnvironment["FASTLANE_SNAPSHOT"] = "1"
    }
}
