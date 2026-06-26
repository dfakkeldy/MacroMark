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
    
    @Test("User-dictated emphasis markers are left untouched")
    func testDictatedMarkersNotMangled() async {
        // §5.7: no macro inserted these markers, so the wrap-cleanup must not collapse
        // them — even though they are spaced like Markdown emphasis.
        let macros: [MacroRule] = []
        let input = "This is * bold text * and ** strong text ** and _ italic _"
        let output = await MacroProcessor.process(text: input, macros: macros)

        #expect(output == input)
    }
}
