import Foundation

public struct ExportManager {
    
    public static func url(for note: ProcessedNote, to target: ExportTarget) -> URL? {
        guard let encodedText = note.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        var urlString = ""
        
        switch target {
        case .drafts:
            // Drafts URL Scheme
            urlString = "drafts://x-callback-url/create?text=\(encodedText)&tag=macromark"
            
        case .dayOne:
            // Day One URL Scheme
            urlString = "dayone://post?entry=\(encodedText)&tags=macromark"
            
        case .obsidian:
            // Obsidian URL Scheme
            urlString = "obsidian://new?content=\(encodedText)"
            
        case .bear:
            // Bear URL Scheme
            urlString = "bear://x-callback-url/create?text=\(encodedText)&tags=macromark"
            
        case .iCloud, .shareSheet:
            // Not handled by URL scheme
            return nil
        }
        
        return URL(string: urlString)
    }
}
