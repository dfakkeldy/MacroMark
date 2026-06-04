import Foundation

public struct FolderSettings: Codable, Equatable {
    public enum FolderStructure: String, Codable, CaseIterable {
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

    public var structure: FolderStructure = .flat
    public var dateFormat: String = "yyyy-MM-dd"

    public init(structure: FolderStructure = .flat, dateFormat: String = "yyyy-MM-dd") {
        self.structure = structure
        self.dateFormat = dateFormat
    }

    /// Format a date using this settings' date format string.
    /// Supports `yyyy`, `yy`, `MM`, and `dd` tokens.
    public func format(date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
        }
        var result = dateFormat
        result = result.replacing("yyyy", with: String(year))
        result = result.replacing("yy", with: String(year % 100))
        result = result.replacing("MM", with: String(format: "%02d", month))
        result = result.replacing("dd", with: String(format: "%02d", day))
        return result
    }
}
