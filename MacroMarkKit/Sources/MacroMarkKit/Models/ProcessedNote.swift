import Foundation
import SwiftData

@Model
public final class ProcessedNote {
    public var idString: String = UUID().uuidString
    public var text: String = ""
    public var createdAt: Date = Date()
    public var isExported: Bool = false
    public var exportTarget: String? = nil
    
    public init(idString: String = UUID().uuidString, text: String, createdAt: Date = Date(), isExported: Bool = false, exportTarget: String? = nil) {
        self.idString = idString
        self.text = text
        self.createdAt = createdAt
        self.isExported = isExported
        self.exportTarget = exportTarget
    }
}
