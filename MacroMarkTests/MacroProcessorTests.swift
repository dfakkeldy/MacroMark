import Testing
import Foundation
import MacroMarkKit
@testable import MacroMark

@Suite("MacroProcessor Tests")
struct MacroProcessorTests {
    
    @Test("Test trigger replacement")
    func testTriggerReplacement() async {
        let macros = [
            MacroRule(trigger: "Heading One", replacement: "# "),
            MacroRule(trigger: "Bold", replacement: "**")
        ]
        
        let input = "Heading One this is bold"
        let output = await MacroProcessor.process(text: input, macros: macros)
        #expect(output == "#  this is **")
    }
    
    @Test("Test case insensitive trigger replacement")
    func testCaseInsensitiveTriggerReplacement() async {
        let macros = [
            MacroRule(trigger: "heading one", replacement: "# ")
        ]
        
        let input = "HEADING ONE this is a test"
        let output = await MacroProcessor.process(text: input, macros: macros)
        #expect(output == "#  this is a test")
    }
    
    @Test("Test variable replacements")
    func testVariableReplacements() async {
        let macros: [MacroRule] = []
        let input = "Today is {date} at {time}{newline}Next line"
        let output = await MacroProcessor.process(text: input, macros: macros)
        
        #expect(!output.contains("{date}"))
        #expect(!output.contains("{time}"))
        #expect(output.contains("\nNext line"))
    }
    
    @Test("Test wrapping tag cleanup")
    func testWrappingTagCleanup() async {
        let macros = [
            MacroRule(trigger: "Bold", replacement: "**"),
            MacroRule(trigger: "Italic", replacement: "_")
        ]
        let input = "This is Bold strong text Bold and Italic emphasized text Italic"
        let output = await MacroProcessor.process(text: input, macros: macros)
        
        #expect(output == "This is **strong text** and _emphasized text_")
    }

    @Test("Test literal asterisks are preserved")
    func testLiteralAsterisksArePreserved() async {
        let output = await MacroProcessor.process(text: "3 * 4 * 5", macros: [])

        #expect(output == "3 * 4 * 5")
    }
}
