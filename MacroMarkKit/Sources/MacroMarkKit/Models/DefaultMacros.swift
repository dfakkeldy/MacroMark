import Foundation

/// The built-in default macros, seeded on first launch and re-applied by
/// "Restore Default Macros". Lives in MacroMarkKit (not in a SwiftUI view) so the
/// seed data can be unit-tested and reused. `sortOrder`s are unique and sequential.
public enum DefaultMacros {
    /// A fresh set of default `Macro` models. Each call returns new instances for
    /// the caller to insert into its `ModelContext`.
    public static func all() -> [Macro] {
        [
            // Markdown headings
            Macro(trigger: "Heading One", replacement: "# ", isDefault: true, sortOrder: 0),
            Macro(trigger: "Heading Two", replacement: "## ", isDefault: true, sortOrder: 1),
            Macro(trigger: "Heading To", replacement: "## ", notes: "Dictation often mishears 'Heading Two' as 'Heading To'.", isDefault: true, sortOrder: 2),
            Macro(trigger: "Heading Three", replacement: "### ", isDefault: true, sortOrder: 3),
            Macro(trigger: "Heading Four", replacement: "#### ", isDefault: true, sortOrder: 4),
            Macro(trigger: "Heading Five", replacement: "##### ", isDefault: true, sortOrder: 5),
            Macro(trigger: "Heading Six", replacement: "###### ", isDefault: true, sortOrder: 6),

            // Markdown formatting
            Macro(trigger: "Bold", replacement: "**", isDefault: true, sortOrder: 7),
            Macro(trigger: "Italic", replacement: "_", isDefault: true, sortOrder: 8),
            Macro(trigger: "Strikethrough", replacement: "~~", isDefault: true, sortOrder: 9),
            Macro(trigger: "Code Block", replacement: "```", isDefault: true, sortOrder: 10),
            Macro(trigger: "Inline Code", replacement: "`", isDefault: true, sortOrder: 11),
            Macro(trigger: "Quote", replacement: "> ", isDefault: true, sortOrder: 12),

            // Markdown lists
            Macro(trigger: "Bullet", replacement: "- ", isDefault: true, sortOrder: 13),
            Macro(trigger: "Numbered", replacement: "1. ", isDefault: true, sortOrder: 14),
            Macro(trigger: "Task", replacement: "- [ ] ", isDefault: true, sortOrder: 15),

            // Clever macros
            Macro(trigger: "Timestamp", replacement: "{time} - ", notes: "Inserts the current time.", isDefault: true, sortOrder: 16),
            Macro(trigger: "New Journal Entry", replacement: "## {date} at {time}", notes: "Creates a new daily journal entry heading.", isDefault: true, sortOrder: 17),
            Macro(trigger: "Horizontal Rule", replacement: "---", isDefault: true, sortOrder: 18),
            Macro(trigger: "Paste", replacement: "{clipboard}", notes: "Pastes whatever is currently on your clipboard.", isDefault: true, sortOrder: 19),
            Macro(trigger: "Dropoff", replacement: "{location} - ", notes: "Inserts your current street address.", isDefault: true, sortOrder: 20),
            Macro(trigger: "Smile", replacement: "😀", isDefault: true, sortOrder: 21),
            Macro(trigger: "Block ID", replacement: "^id-{uuid}", notes: "Generates a unique identifier for block references.", isDefault: true, sortOrder: 22),
            Macro(trigger: "Not", replacement: "{backspace}", notes: "Deletes the character before it. Say 'new line' then 'not' to end a hashtag without leaving a newline. ⚠️ 'Not' is a common word — rename this trigger if it fires accidentally.", isDefault: true, sortOrder: 23),
        ]
    }
}
