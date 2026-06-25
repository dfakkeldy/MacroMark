import Foundation

public struct PendingExportEntry: Codable, Equatable, Sendable {
    public var noteId: UUID
    public var processedText: String
    public var timestamp: Date
    public var isAudio: Bool
    public var requiresWatchAcknowledgement: Bool

    public init(
        noteId: UUID = UUID(),
        processedText: String,
        timestamp: Date,
        isAudio: Bool,
        requiresWatchAcknowledgement: Bool = true
    ) {
        self.noteId = noteId
        self.processedText = processedText
        self.timestamp = timestamp
        self.isAudio = isAudio
        self.requiresWatchAcknowledgement = requiresWatchAcknowledgement
    }

    private enum CodingKeys: String, CodingKey {
        case noteId
        case processedText
        case timestamp
        case isAudio
        case requiresWatchAcknowledgement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noteId = try container.decode(UUID.self, forKey: .noteId)
        processedText = try container.decode(String.self, forKey: .processedText)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isAudio = try container.decode(Bool.self, forKey: .isAudio)
        requiresWatchAcknowledgement = try container.decodeIfPresent(Bool.self, forKey: .requiresWatchAcknowledgement) ?? true
    }
}

public enum PendingExportStore {
    public static func read(userDefaults: UserDefaults = .standard) -> [UUID: PendingExportEntry] {
        guard let data = userDefaults.data(forKey: UserDefaultsKey.pendingExports.rawValue),
              let dict = try? JSONDecoder().decode([String: PendingExportEntry].self, from: data)
        else { return [:] }

        return dict.reduce(into: [:]) { partial, entry in
            if let id = UUID(uuidString: entry.key) {
                partial[id] = entry.value
            }
        }
    }

    public static func upsert(_ entry: PendingExportEntry, userDefaults: UserDefaults = .standard) {
        var pending = read(userDefaults: userDefaults)
        pending[entry.noteId] = entry
        write(pending, userDefaults: userDefaults)
    }

    public static func remove(id: UUID, userDefaults: UserDefaults = .standard) {
        var pending = read(userDefaults: userDefaults)
        pending.removeValue(forKey: id)
        write(pending, userDefaults: userDefaults)
    }

    public static func firstEntry(
        processedText: String,
        timestamp: Date,
        userDefaults: UserDefaults = .standard
    ) -> PendingExportEntry? {
        read(userDefaults: userDefaults).values.first {
            $0.processedText == processedText && $0.timestamp == timestamp
        }
    }

    public static func removeMatching(
        processedText: String,
        timestamp: Date,
        userDefaults: UserDefaults = .standard
    ) {
        var pending = read(userDefaults: userDefaults)
        pending = pending.filter { _, entry in
            entry.processedText != processedText || entry.timestamp != timestamp
        }
        write(pending, userDefaults: userDefaults)
    }

    private static func write(_ dict: [UUID: PendingExportEntry], userDefaults: UserDefaults) {
        let stringDict = dict.reduce(into: [String: PendingExportEntry]()) { partial, entry in
            partial[entry.key.uuidString] = entry.value
        }
        if let data = try? JSONEncoder().encode(stringDict) {
            userDefaults.set(data, forKey: UserDefaultsKey.pendingExports.rawValue)
        }
    }
}
