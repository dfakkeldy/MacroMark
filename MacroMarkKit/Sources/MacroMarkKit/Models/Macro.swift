import Foundation
import SwiftData

@Model
public final class Macro {
    public var trigger: String = ""
    public var replacement: String = ""
    public var isDefault: Bool = false
    public var isDefaultEdited: Bool = false
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()

    public init(trigger: String, replacement: String, isDefault: Bool = false, sortOrder: Int = 0) {
        self.trigger = trigger
        self.replacement = replacement
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}
