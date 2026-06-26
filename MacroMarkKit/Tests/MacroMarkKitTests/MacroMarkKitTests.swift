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
        var settings = FolderSettings(structure: .yearlyMonthly, dateFormat: "MM-dd-yyyy")
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(FolderSettings.self, from: data)

        #expect(decoded.structure == .yearlyMonthly)
        #expect(decoded.dateFormat == "MM-dd-yyyy")
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

    /// §5.7: the wrapping-tag cleanup must tidy markers a MACRO inserted —
    /// "make this ** word **" → "make this **word**".
    @Test
    func macroInsertedMarkersAreTidied() async {
        let macros = [MacroRule(trigger: "bold", replacement: "**")]
        let result = await MacroProcessor.process(text: "make this bold word bold", macros: macros)
        #expect(result == "make this **word**")
    }

    /// §5.7 regression: but it must NEVER collapse `*`/`_`/`~` the user dictated,
    /// even when spaced like Markdown emphasis (which the old global cleanup did).
    @Test
    func dictatedSymbolsArePreserved() async {
        #expect(await MacroProcessor.process(text: "3 * 4 * 5", macros: []) == "3 * 4 * 5")
        #expect(await MacroProcessor.process(text: "a _ b _ c", macros: []) == "a _ b _ c")
        #expect(await MacroProcessor.process(text: "x ~ y ~ z", macros: []) == "x ~ y ~ z")
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
