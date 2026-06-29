import Foundation

public struct ExportManager {
    
    public static func url(for note: ProcessedNote, to target: ExportTarget) -> URL? {
        var components = URLComponents()

        switch target {
        case .drafts:
            components.scheme = "drafts"
            components.host = "x-callback-url"
            components.path = "/create"
            components.queryItems = [
                URLQueryItem(name: "text", value: note.text),
                URLQueryItem(name: "tag", value: "macromark")
            ]
            
        case .dayOne:
            components.scheme = "dayone"
            components.host = "post"
            components.queryItems = [
                URLQueryItem(name: "entry", value: note.text),
                URLQueryItem(name: "tags", value: "macromark")
            ]
            
        case .obsidian:
            components.scheme = "obsidian"
            components.host = "new"
            components.queryItems = [
                URLQueryItem(name: "content", value: note.text)
            ]
            
        case .bear:
            components.scheme = "bear"
            components.host = "x-callback-url"
            components.path = "/create"
            components.queryItems = [
                URLQueryItem(name: "text", value: note.text),
                URLQueryItem(name: "tags", value: "macromark")
            ]
            
        case .iCloud, .shareSheet:
            return nil
        }

        return components.url
    }
}
