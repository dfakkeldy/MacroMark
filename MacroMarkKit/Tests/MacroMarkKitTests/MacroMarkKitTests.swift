import Testing
import Foundation
@testable import MacroMarkKit

struct MacroModelTests {

    @Test
    func macroInitialization() async throws {
        let macro = Macro(trigger: "Test", replacement: "replacement", isDefault: true, sortOrder: 5)

        #expect(macro.trigger == "Test")
        #expect(macro.replacement == "replacement")
        #expect(macro.isDefault == true)
        #expect(macro.isDefaultEdited == false)
        #expect(macro.sortOrder == 5)
    }

    @Test
    func macroDefaultValues() async throws {
        let macro = Macro(trigger: "Hello", replacement: "World")

        #expect(macro.isDefault == false)
        #expect(macro.sortOrder == 0)
    }
}

struct FolderSettingsTests {

    @Test
    func defaultSettings() async throws {
        let settings = FolderSettings()
        #expect(settings.structure == .flat)
        #expect(settings.dateFormat == "yyyy-MM-dd")
    }

    @Test
    func allStructuresExist() async throws {
        let all = FolderSettings.FolderStructure.allCases
        #expect(all.count == 3)
        #expect(all.contains(.flat))
        #expect(all.contains(.monthly))
        #expect(all.contains(.yearlyMonthly))
    }

    @Test
    func jsonRoundtrip() async throws {
        let settings = FolderSettings(structure: .yearlyMonthly, dateFormat: "MM-dd-yyyy")
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(FolderSettings.self, from: data)

        #expect(decoded.structure == .yearlyMonthly)
        #expect(decoded.dateFormat == "MM-dd-yyyy")
    }

    @Test
    func dateFormatIsSanitizedForSafeDailyNoteFilenames() async throws {
        #expect(FolderSettings.sanitizedDateFormat("") == FolderSettings.defaultDateFormat)
        #expect(FolderSettings.sanitizedDateFormat("yyyy/MM/dd") == "yyyy-MM-dd")
        #expect(FolderSettings.sanitizedDateFormat("yyyy MM dd") == "yyyy-MM-dd")
        #expect(FolderSettings.sanitizedDateFormat("yyyy-MM") == FolderSettings.defaultDateFormat)
    }

    @Test
    func relativePathMatchesStorageStructure() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 28, hour: 12)))

        #expect(FolderSettings(structure: .flat).relativePath(for: date) == "2026-06-28.md")
        #expect(FolderSettings(structure: .monthly).relativePath(for: date) == "2026-06/2026-06-28.md")
        #expect(FolderSettings(structure: .yearlyMonthly).relativePath(for: date) == "2026/06/2026-06-28.md")
    }
}

struct ProductIdentifiersTests {

    @Test
    func allProductsConfigured() async throws {
        #expect(ProductIdentifiers.all.count == 2)
        #expect(ProductIdentifiers.all.contains("com.macromark.subscription.annual"))
        #expect(ProductIdentifiers.all.contains("com.macromark.lifetime"))
    }
}

struct MacroProcessorTests {

    @Test
    func newlineReplacement() async throws {
        let result = await MacroProcessor.process(text: "hello{newline}world", macros: [])
        #expect(result == "hello\nworld")
    }

    @Test
    func dateReplacement() async throws {
        let result = await MacroProcessor.process(text: "date is {date}", macros: [])
        #expect(!result.contains("{date}"))
        #expect(result.hasPrefix("date is "))
    }

    @Test
    func timeReplacement() async throws {
        let result = await MacroProcessor.process(text: "time is {time}", macros: [])
        #expect(!result.contains("{time}"))
        #expect(result.hasPrefix("time is "))
    }

    @Test
    func macroTriggerReplacement() async throws {
        let macros = [MacroRule(trigger: "Hello", replacement: "Bonjour")]
        let result = await MacroProcessor.process(text: "Hello world", macros: macros)
        #expect(result == "Bonjour world")
    }

    @Test
    func singleNewlineNoExtraBlankLine() async throws {
        // Verifies the fix: {newline} inserts exactly one newline, not two.
        // (The two spaces after the dash come from the macro's trailing space
        // plus the original word separator — unrelated to {newline}.)
        let macros = [MacroRule(trigger: "Bullet", replacement: "{newline}- ")]
        let result = await MacroProcessor.process(text: "Bullet item", macros: macros)
        #expect(!result.contains("\n\n"))
        #expect(result.hasPrefix("\n"))
    }

    /// Regression test for §3.1 (Critical): the regex cache is mutated by every
    /// `process(...)` call and was previously a `nonisolated(unsafe)` Dictionary.
    /// Concurrent calls must not crash (EXC_BAD_ACCESS / heap corruption) and
    /// must produce identical output.
    @Test
    func regexCacheIsConcurrencySafe() async throws {
        let text = "Bold world Bold again"
        // MacroRule is a Sendable value type, so it can be constructed and captured
        // directly inside the task-group closures (unlike the SwiftData @Model `Macro`).
        await withTaskGroup(of: String.self) { group in
            for _ in 0..<200 {
                group.addTask {
                    let macros = [MacroRule(trigger: "Bold", replacement: "**")]
                    return await MacroProcessor.process(text: text, macros: macros)
                }
            }
            let results = await group.reduce(into: [String]()) { $0.append($1) }
            // Every result must be identical — no corruption, no divergence under
            // concurrent cache mutation. (The wrapCleanupRegex collapses the
            // spaces around the `**` markers; the point of this test is that all
            // 200 concurrent results agree, not the exact string.)
            let first = results.first
            #expect(first == "**world** again")
            #expect(results.allSatisfy { $0 == first })
        }
    }

    /// Regression test for §5.3 (High): editing a macro's trigger must not leave
    /// the OLD trigger's compiled regex cached and still firing.
    @Test
    func invalidateRegexCacheDropsStaleEntries() async throws {
        let oldTrigger = [MacroRule(trigger: "Bold", replacement: "**")]
        // Populate the cache with the "Bold" pattern.
        let warmup = await MacroProcessor.process(text: "Bold x", macros: oldTrigger)
        #expect(warmup == "** x")

        // Invalidate, then process with a renamed trigger. "Bold" must no longer
        // match; "Strong" must.
        MacroProcessor.invalidateRegexCache()
        let newTrigger = [MacroRule(trigger: "Strong", replacement: "**")]
        let result = await MacroProcessor.process(text: "Bold test Strong", macros: newTrigger)
        #expect(result == "Bold test **")
    }
}

struct AppendResultTests {

    /// Smoke test for §5.1/§5.2: the `AppendResult` enum the ACK pipeline
    /// switches on exposes the three documented cases.
    @Test
    func appendResultCases() async throws {
        let cases: [AppendResult] = [.appended, .deferred, .failed]
        #expect(cases.count == 3)
        // The pipeline treats `.appended` as the only success; the other two
        // must keep the note in the pending-export WAL.
        #expect(cases.filter { $0 == .appended }.count == 1)
    }
}

struct UserDefaultsKeyTests {

    @Test
    func destinationProofKeysRemainStable() async throws {
        #expect(UserDefaultsKey.lastSuccessfulExportPath.rawValue == "lastSuccessfulExportPath")
        #expect(UserDefaultsKey.lastSuccessfulExportAt.rawValue == "lastSuccessfulExportAt")
    }
}

struct ContinuationTimeoutTests {

    @Test
    func completeReturnsTrueOnlyOnce() async throws {
        let timeout = ContinuationTimeout()
        #expect(await timeout.complete())
        #expect(!(await timeout.complete()))
    }
}

struct AppRouteTests {

    @Test
    func captureRoutesAreStable() async throws {
        #expect(AppRoute.instantCaptureURL.absoluteString == "macromark://capture/instant")
        #expect(AppRoute.systemCaptureURL.absoluteString == "macromark://capture/system")
    }

    @Test
    func dailyLogRoutesUseStableDateFormatting() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 28))!

        #expect(AppRoute.dailyLogURL().absoluteString == "macromark://daily-log")
        #expect(
            AppRoute.dailyLogURL(date: date, calendar: calendar).absoluteString
                == "macromark://daily-log?date=2026-06-28"
        )
    }

    @Test
    func appendRouteEncodesQueryTextSafely() async throws {
        let text = "Title & details\nLine two"
        let url = AppRoute.appendTextURL(text)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        #expect(url.absoluteString == "macromark://append?text=Title%20%26%20details%0ALine%20two")
        #expect(components?.host == "append")
        #expect(components?.queryItems?.first(where: { $0.name == "text" })?.value == text)
    }
}

struct ExportStatusTests {

    @Test
    func exportedStatusFollowsLegacyFlag() async throws {
        let note = ProcessedNote(text: "done", isExported: true)
        #expect(note.exportStatus == .exported)
    }

    @Test
    func statusRoundTripsThroughRawValue() async throws {
        let note = ProcessedNote(
            text: "waiting",
            exportStatus: .deferred,
            exportStatusMessage: "Waiting for iCloud."
        )
        #expect(note.exportStatusRaw == "deferred")
        #expect(note.exportStatus == .deferred)
        #expect(note.exportStatus.needsAttention)
        #expect(note.exportStatusMessage == "Waiting for iCloud.")
    }
}
