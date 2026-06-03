import Foundation
import SwiftData

@Model
final class Macro {
    var trigger: String = ""
    var replacement: String = ""
    var createdAt: Date = Date()
    
    init(trigger: String, replacement: String) {
        self.trigger = trigger
        self.replacement = replacement
        self.createdAt = Date()
    }
}
