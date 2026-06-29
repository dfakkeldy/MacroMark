import Foundation

public enum PendingExportStore {
    public static func read(from defaults: UserDefaults = .standard) -> [UUID: PendingExportRecord] {
        guard let data = defaults.data(forKey: UserDefaultsKey.pendingExports.rawValue),
              let dict = try? JSONDecoder().decode([String: PendingExportRecord].self, from: data)
        else { return [:] }

        return dict.reduce(into: [:]) { partial, entry in
            if let id = UUID(uuidString: entry.key) {
                partial[id] = entry.value
            }
        }
    }

    public static func write(
        _ dict: [UUID: PendingExportRecord],
        to defaults: UserDefaults = .standard
    ) throws {
        let stringDict = dict.reduce(into: [String: PendingExportRecord]()) {
            $0[$1.key.uuidString] = $1.value
        }
        let data = try JSONEncoder().encode(stringDict)
        defaults.set(data, forKey: UserDefaultsKey.pendingExports.rawValue)
        guard defaults.synchronize() else {
            throw PendingExportStoreError.userDefaultsWriteFailed
        }
    }

    public static func upsert(
        _ entry: PendingExportRecord,
        in defaults: UserDefaults = .standard
    ) throws {
        var pending = read(from: defaults)
        pending[entry.noteId] = entry
        try write(pending, to: defaults)
    }

    public static func remove(
        id: UUID,
        from defaults: UserDefaults = .standard
    ) throws {
        var pending = read(from: defaults)
        pending.removeValue(forKey: id)
        try write(pending, to: defaults)
    }
}

public enum PendingExportStoreError: Error {
    case userDefaultsWriteFailed
}

public struct PendingExportRecord: Codable, Equatable {
    public var noteId: UUID
    public var processedText: String
    public var timestamp: Date
    public var targetRawValue: String
    public var isAudio: Bool
    public var requiresWatchAcknowledgement: Bool

    public init(
        noteId: UUID,
        processedText: String,
        timestamp: Date,
        target: ExportTarget,
        isAudio: Bool,
        requiresWatchAcknowledgement: Bool = true
    ) {
        self.noteId = noteId
        self.processedText = processedText
        self.timestamp = timestamp
        self.targetRawValue = target.rawValue
        self.isAudio = isAudio
        self.requiresWatchAcknowledgement = requiresWatchAcknowledgement
    }

    public var target: ExportTarget {
        ExportTarget(rawValue: targetRawValue) ?? .iCloud
    }

    private enum CodingKeys: String, CodingKey {
        case noteId
        case processedText
        case timestamp
        case targetRawValue
        case isAudio
        case requiresWatchAcknowledgement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noteId = try container.decode(UUID.self, forKey: .noteId)
        processedText = try container.decode(String.self, forKey: .processedText)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        targetRawValue = try container.decodeIfPresent(String.self, forKey: .targetRawValue)
            ?? ExportTarget.iCloud.rawValue
        isAudio = try container.decode(Bool.self, forKey: .isAudio)
        requiresWatchAcknowledgement = try container.decodeIfPresent(
            Bool.self,
            forKey: .requiresWatchAcknowledgement
        ) ?? true
    }
}
