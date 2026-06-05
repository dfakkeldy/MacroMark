import Foundation
import SwiftData

@Model
public final class ProcessedNote {
    public var text: String = ""
    public var createdAt: Date = Date()
    public var isExported: Bool = false
    public var exportTarget: String? = nil

    public init(text: String, createdAt: Date = Date(), isExported: Bool = false, exportTarget: String? = nil) {
        self.text = text
        self.createdAt = createdAt
        self.isExported = isExported
        self.exportTarget = exportTarget
    }
}
