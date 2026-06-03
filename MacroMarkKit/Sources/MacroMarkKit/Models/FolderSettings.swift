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
}
