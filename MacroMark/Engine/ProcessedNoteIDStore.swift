import Foundation
import MacroMarkKit

enum ProcessedNoteIDStore {
    static func loadOrder(from defaults: UserDefaults = .standard) -> [UUID] {
        let strings = defaults.stringArray(forKey: UserDefaultsKey.processedNoteIDs.rawValue) ?? []
        var seen = Set<UUID>()
        return strings.compactMap(UUID.init(uuidString:)).filter { seen.insert($0).inserted }
    }

    static func saveOrder(_ order: [UUID], to defaults: UserDefaults = .standard) {
        defaults.set(order.map(\.uuidString), forKey: UserDefaultsKey.processedNoteIDs.rawValue)
    }

    static func inserting(_ id: UUID, into order: [UUID], maxCount: Int) -> [UUID] {
        var updated = order.filter { $0 != id }
        updated.append(id)

        if updated.count > maxCount {
            updated.removeFirst(updated.count - maxCount)
        }

        return updated
    }
}
