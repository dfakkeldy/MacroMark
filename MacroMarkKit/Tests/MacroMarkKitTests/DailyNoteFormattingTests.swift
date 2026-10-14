import Foundation
import Testing
@testable import MacroMarkKit

struct DailyNoteFormattingTests {
    @Test
    func defaultEntryContainsTextAndSpacing() throws {
        let date = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 6, day: 28, hour: 9, minute: 30)
            )
        )
        let entry = DailyNoteFormatter.renderEntry(text: "Captured text", timestamp: date)

        #expect(entry.hasPrefix("\n\n"))
        #expect(entry.contains("Captured text"))
        #expect(entry.hasSuffix("\n\n"))
    }

    @Test
    func horizontalRuleAndHeadingRenderBeforeText() throws {
        let date = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 6, day: 28, hour: 9, minute: 30)
            )
        )
        let formatting = DailyNoteFormatting(
            timestampStyle: .none,
            separator: .horizontalRule,
            appendHeading: "## Captures"
        )

        let entry = DailyNoteFormatter.renderEntry(text: "Line", timestamp: date, formatting: formatting)

        #expect(entry.contains("---\n\n## Captures\n\nLine"))
    }
}
