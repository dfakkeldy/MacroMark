import Foundation
import SwiftData
import MacroMarkKit

enum ScreenshotMode {
    static let launchArgument = "--screenshot-mode"
    static let uiTestArgument = "--ui-test-mode"
    static let uiTestEnvironmentKey = "MACROMARK_UI_TEST_MODE"
    static let referenceDate: Date = .now

    static var isEnabled: Bool {
        CommandLine.arguments.contains(launchArgument)
            || CommandLine.arguments.contains(uiTestArgument)
            || CommandLine.arguments.contains("-FASTLANE_SNAPSHOT")
            || CommandLine.arguments.contains("-ui_testing")
            || ProcessInfo.processInfo.environment["MACROMARK_SCREENSHOT_MODE"] == "1"
            || ProcessInfo.processInfo.environment[uiTestEnvironmentKey] == "1"
            || ProcessInfo.processInfo.environment["FASTLANE_SNAPSHOT"] == "1"
    }

    @MainActor private static var didSeed = false

    static func configureDefaults() {
        guard isEnabled else { return }

        let defaults = UserDefaults.standard
        defaults.set("audio", forKey: UserDefaultsKey.captureMode.rawValue)
        defaults.set(ExportTarget.iCloud.rawValue, forKey: UserDefaultsKey.defaultExportTarget.rawValue)
        defaults.set(false, forKey: UserDefaultsKey.autoExportEnabled.rawValue)
        defaults.removeObject(forKey: UserDefaultsKey.customSaveBookmark.rawValue)
        defaults.removeObject(forKey: UserDefaultsKey.pendingProcessing.rawValue)
        defaults.removeObject(forKey: UserDefaultsKey.pendingAudioIn.rawValue)
        defaults.removeObject(forKey: UserDefaultsKey.pendingExports.rawValue)
        defaults.removeObject(forKey: UserDefaultsKey.processedNoteIDs.rawValue)
    }

    @MainActor
    static func seedIfNeeded(in modelContext: ModelContext) {
        guard isEnabled, !didSeed else { return }

        do {
            try deleteExistingScreenshotData(in: modelContext)
            for macro in previewMacros {
                modelContext.insert(macro)
            }
            for note in previewNotes {
                modelContext.insert(note)
            }
            try modelContext.save()
            didSeed = true
        } catch {
#if DEBUG
            print("MacroMark screenshot seed failed: \(error)")
#endif
        }
    }

    @MainActor
    private static func deleteExistingScreenshotData(in modelContext: ModelContext) throws {
        for macro in try modelContext.fetch(FetchDescriptor<Macro>()) {
            modelContext.delete(macro)
        }
        for note in try modelContext.fetch(FetchDescriptor<ProcessedNote>()) {
            modelContext.delete(note)
        }
    }

    static var previewMacros: [Macro] {
        [
            Macro(
                trigger: "Standup",
                replacement: "## Standup\n- Yesterday:\n- Today:\n- Blockers:",
                notes: "Expands a daily check-in template.",
                sortOrder: 0
            ),
            Macro(
                trigger: "Capture Idea",
                replacement: "## Idea\n{time} - ",
                notes: "Turns a quick thought into a timestamped Markdown note.",
                sortOrder: 1
            ),
            Macro(trigger: "Heading Two", replacement: "## ", isDefault: true, sortOrder: 2),
            Macro(trigger: "Task", replacement: "- [ ] ", isDefault: true, sortOrder: 3),
            Macro(trigger: "Quote", replacement: "> ", isDefault: true, sortOrder: 4),
            Macro(
                trigger: "Dropoff",
                replacement: "{location} - ",
                notes: "Inserts the capture location when location access is available.",
                isDefault: true,
                sortOrder: 5
            )
        ]
    }

    static var previewNotes: [ProcessedNote] {
        [
            ProcessedNote(
                text: """
                ## Standup
                - Shipped App Store metadata
                - Wire screenshot automation
                - Verify iCloud daily note export
                """,
                createdAt: today(hour: 16, minute: 5),
                isExported: true,
                exportTarget: ExportTarget.iCloud.rawValue
            ),
            ProcessedNote(
                text: """
                Meeting follow-up
                - [ ] Send beta invite
                - [ ] Draft release notes
                Decision: keep notes as plain Markdown.
                """,
                createdAt: today(hour: 11, minute: 20),
                isExported: true,
                exportTarget: ExportTarget.iCloud.rawValue
            ),
            ProcessedNote(
                text: "Idea: double tap on Apple Watch starts a durable audio capture.",
                createdAt: today(hour: 9, minute: 35),
                isExported: false,
                transcriptionPartial: true
            )
        ]
    }

    private static func today(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: referenceDate) ?? referenceDate
    }
}
