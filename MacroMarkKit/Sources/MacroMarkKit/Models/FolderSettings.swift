import Foundation

public struct FolderSettings: Codable, Equatable, Sendable {
    public enum FolderStructure: String, Codable, CaseIterable, Sendable {
        case flat
        case monthly
        case yearlyMonthly

        public var displayName: String {
            switch self {
            case .flat: return "Flat (All in One Folder)"
            case .monthly: return "Monthly Folders"
            case .yearlyMonthly: return "Yearly / Monthly Folders"
            }
        }
    }

    public static let defaultDateFormat = "yyyy-MM-dd"

    public var structure: FolderStructure = .flat
    public var dateFormat: String = Self.defaultDateFormat

    public init(structure: FolderStructure = .flat, dateFormat: String = Self.defaultDateFormat) {
        self.structure = structure
        self.dateFormat = Self.sanitizedDateFormat(dateFormat)
    }

    private enum CodingKeys: String, CodingKey {
        case structure
        case dateFormat
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        structure = try container.decodeIfPresent(FolderStructure.self, forKey: .structure) ?? .flat
        let rawDateFormat = try container.decodeIfPresent(String.self, forKey: .dateFormat)
            ?? Self.defaultDateFormat
        dateFormat = Self.sanitizedDateFormat(rawDateFormat)
    }

    public static func sanitizedDateFormat(_ rawValue: String) -> String {
        var sanitized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return defaultDateFormat }

        sanitized = sanitized.replacing("\\", with: "-")
            .replacing("/", with: "-")
            .replacing(":", with: "-")
            .replacing("*", with: "-")
            .replacing("?", with: "-")
            .replacing("\"", with: "-")
            .replacing("<", with: "-")
            .replacing(">", with: "-")
            .replacing("|", with: "-")

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        sanitized = String(
            sanitized.unicodeScalars.map { scalar in
                allowed.contains(scalar) ? Character(scalar) : "-"
            }
        )

        while sanitized.contains("--") {
            sanitized = sanitized.replacing("--", with: "-")
        }
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))

        let hasYear = sanitized.contains("yyyy") || sanitized.contains("yy")
        let hasMonth = sanitized.contains("MM")
        let hasDay = sanitized.contains("dd")
        guard hasYear, hasMonth, hasDay else { return defaultDateFormat }

        return sanitized.isEmpty ? defaultDateFormat : sanitized
    }

    /// Format a date using this settings' date format string.
    /// Supports `yyyy`, `yy`, `MM`, and `dd` tokens.
    public func format(date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
        }
        var result = Self.sanitizedDateFormat(dateFormat)
        result = result.replacing("yyyy", with: String(year))
        result = result.replacing("yy", with: twoDigitString(year % 100))
        result = result.replacing("MM", with: twoDigitString(month))
        result = result.replacing("dd", with: twoDigitString(day))
        return result
    }

    public func relativePath(for date: Date) -> String {
        let filename = format(date: date) + ".md"

        switch structure {
        case .flat:
            return filename
        case .monthly:
            let year = date.formatted(Date.FormatStyle().year())
            let month = date.formatted(Date.FormatStyle().month(.twoDigits))
            return "\(year)-\(month)/\(filename)"
        case .yearlyMonthly:
            let year = date.formatted(Date.FormatStyle().year())
            let month = date.formatted(Date.FormatStyle().month(.twoDigits))
            return "\(year)/\(month)/\(filename)"
        }
    }

    private func twoDigitString(_ value: Int) -> String {
        value.formatted(.number.precision(.integerLength(2)).grouping(.never))
    }
}
