import AppIntents
import Foundation
import MacroMarkKit

struct StartInstantCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Instant Capture"
    static let description = IntentDescription("Open MacroMark's instant capture route.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppRoute.instantCaptureURL))
    }
}

struct StartTypedCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Typed Capture"
    static let description = IntentDescription("Open MacroMark's typed capture route.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppRoute.systemCaptureURL))
    }
}

struct OpenDailyLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Daily Log"
    static let description = IntentDescription("Open MacroMark's daily log for a selected date.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Date")
    var date: Date?

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppRoute.dailyLogURL(date: date)))
    }
}

struct AppendTextToTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Append Text to Today"
    static let description = IntentDescription("Open MacroMark and append text through the daily-note export flow.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Text")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(AppRoute.appendTextURL(text)))
    }
}

struct MacroMarkShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartInstantCaptureIntent(),
            phrases: [
                "Start instant capture in \(.applicationName)",
                "Capture a note in \(.applicationName)"
            ],
            shortTitle: "Instant Capture",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: StartTypedCaptureIntent(),
            phrases: [
                "Start typed capture in \(.applicationName)",
                "Type a note in \(.applicationName)"
            ],
            shortTitle: "Typed Capture",
            systemImageName: "keyboard"
        )

        AppShortcut(
            intent: OpenDailyLogIntent(),
            phrases: [
                "Open daily log in \(.applicationName)",
                "Show today's notes in \(.applicationName)"
            ],
            shortTitle: "Daily Log",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: AppendTextToTodayIntent(),
            phrases: [
                "Append text in \(.applicationName)",
                "Save a quick note in \(.applicationName)"
            ],
            shortTitle: "Append Text",
            systemImageName: "square.and.pencil"
        )
    }
}
