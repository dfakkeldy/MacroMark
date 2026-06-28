import Foundation

public struct DailyNoteFormatting: Codable, Equatable {
    public var timestampStyle: TimestampStyle
    public var separator: Separator
    public var appendHeading: String

    public init(
        timestampStyle: TimestampStyle = .timeOnly,
        separator: Separator = .blankLine,
        appendHeading: String = ""
    ) {
        self.timestampStyle = timestampStyle
        self.separator = separator
        self.appendHeading = appendHeading
    }

    public enum TimestampStyle: String, Codable, CaseIterable, Identifiable {
        case none
        case timeOnly
        case fullDateTime

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .none:
                "None"
            case .timeOnly:
                "Time Only"
            case .fullDateTime:
                "Full Date & Time"
            }
        }
    }

    public enum Separator: String, Codable, CaseIterable, Identifiable {
        case blankLine
        case horizontalRule

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .blankLine:
                "Blank Line"
            case .horizontalRule:
                "Horizontal Rule"
            }
        }
    }
}

public enum DailyNoteFormatter {
    public static func renderEntry(
        text: String,
        timestamp: Date,
        formatting: DailyNoteFormatting = DailyNoteFormatting()
    ) -> String {
        var chunks: [String] = []

        switch formatting.separator {
        case .blankLine:
            break
        case .horizontalRule:
            chunks.append("---")
        }

        let trimmedHeading = formatting.appendHeading.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHeading.isEmpty {
            chunks.append(trimmedHeading)
        }

        switch formatting.timestampStyle {
        case .none:
            break
        case .timeOnly:
            chunks.append(timestamp.formatted(date: .omitted, time: .shortened))
        case .fullDateTime:
            chunks.append(timestamp.formatted(date: .abbreviated, time: .shortened))
        }

        chunks.append(text)
        return "\n\n" + chunks.joined(separator: "\n\n") + "\n\n"
    }
}
