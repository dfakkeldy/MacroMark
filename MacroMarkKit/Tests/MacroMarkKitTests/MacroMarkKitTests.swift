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
        let macros = [Macro(trigger: "Hello", replacement: "Bonjour")]
        let result = await MacroProcessor.process(text: "Hello world", macros: macros)
        #expect(result == "Bonjour world")
    }

    @Test
    func singleNewlineNoExtraBlankLine() async throws {
        // Verifies the fix: {newline} inserts exactly one newline, not two
        let macros = [Macro(trigger: "Bullet", replacement: "{newline}- ")]
        let result = await MacroProcessor.process(text: "Bullet item", macros: macros)
        #expect(result == "\n- item")
    }
}
