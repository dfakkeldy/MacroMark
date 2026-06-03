import Testing
import Foundation
@testable import MacroMark

@Suite("MacroProcessor Tests")
struct MacroProcessorTests {
    
    @Test("Test trigger replacement")
    func testTriggerReplacement() {
        let macros = [
            Macro(trigger: "Heading One", replacement: "# "),
            Macro(trigger: "Bold", replacement: "**")
        ]
        
        let input = "Heading One this is bold"
        let output = MacroProcessor.process(text: input, macros: macros)
        #expect(output == "# this is bold")
    }
    
    @Test("Test case insensitive trigger replacement")
    func testCaseInsensitiveTriggerReplacement() {
        let macros = [
            Macro(trigger: "heading one", replacement: "# ")
        ]
        
        let input = "HEADING ONE this is a test"
        let output = MacroProcessor.process(text: input, macros: macros)
        #expect(output == "# this is a test")
    }
    
    @Test("Test variable replacements")
    func testVariableReplacements() {
        let macros: [Macro] = []
        let input = "Today is {date} at {time}{newline}Next line"
        let output = MacroProcessor.process(text: input, macros: macros)
        
        #expect(!output.contains("{date}"))
        #expect(!output.contains("{time}"))
        #expect(output.contains("\nNext line"))
    }
    
    @Test("Test wrapping tag cleanup")
    func testWrappingTagCleanup() {
        let macros: [Macro] = []
        let input = "This is * bold text * and ** strong text ** and _ italic _"
        let output = MacroProcessor.process(text: input, macros: macros)
        
        #expect(output == "This is *bold text* and **strong text** and _italic_")
    }
}
