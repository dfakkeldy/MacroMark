import Foundation

public enum ExportTarget: String, CaseIterable, Identifiable, Codable {
    case iCloud = "iCloud Drive"
    case drafts = "Drafts"
    case obsidian = "Obsidian"
    case bear = "Bear"
    case dayOne = "Day One"
    case shareSheet = "Share Sheet"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .iCloud: return "icloud.fill"
        case .drafts: return "text.bubble.fill"
        case .obsidian: return "folder.fill"
        case .bear: return "pawprint.fill"
        case .dayOne: return "book.fill"
        case .shareSheet: return "square.and.arrow.up"
        }
    }
}
