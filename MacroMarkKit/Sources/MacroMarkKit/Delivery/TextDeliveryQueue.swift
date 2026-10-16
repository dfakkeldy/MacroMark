import Foundation
import Observation

fileprivate struct DestinationProgress: Codable, Equatable, Sendable {
    var delivered = false
    var attempts = 0
    var nextAttemptAt: Date?
}

public struct CapturedNote: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let timestamp: Date
    public let captureUTCOffsetSeconds: Int
    public let route: TextDeliveryRoute
    fileprivate var progress: [DirectDestination: DestinationProgress]

    public init(id: UUID = UUID(), text: String, timestamp: Date = Date(),
                timeZone: TimeZone = .current, route: TextDeliveryRoute = .phone) {
        self.id = id
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timestamp = timestamp
        captureUTCOffsetSeconds = timeZone.secondsFromGMT(for: timestamp)
        self.route = route
        if case let .direct(_, destinations) = route {
            progress = Dictionary(uniqueKeysWithValues: destinations.map { ($0, DestinationProgress()) })
        } else {
            progress = [:]
        }
    }

    public var captureDay: String { formattedTimestamp("yyyy-MM-dd") }
    public var capturedAtISO8601: String { formattedTimestamp("yyyy-MM-dd'T'HH:mm:ssXXXXX") }
    public var deliveryMarker: String { "<!-- mm:\(id.uuidString.lowercased()) -->" }

    public var pendingDestinations: Set<DirectDestination> {
        Set(progress.compactMap { $0.value.delivered ? nil : $0.key })
    }

    public func eligibleDestinations(at date: Date) -> Set<DirectDestination> {
        Set(progress.compactMap { destination, state in
            !state.delivered && (state.nextAttemptAt == nil || state.nextAttemptAt! <= date) ? destination : nil
        })
    }

    public var nextAttemptAt: Date? {
        progress.values.filter { !$0.delivered }.map { $0.nextAttemptAt ?? .distantPast }.min()
    }

    public func retryDate(for destination: DirectDestination) -> Date? {
        guard let state = progress[destination], !state.delivered else { return nil }
        return state.nextAttemptAt ?? .distantPast
    }

    private func formattedTimestamp(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: captureUTCOffsetSeconds)
        formatter.dateFormat = format
        return formatter.string(from: timestamp)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, timestamp, captureUTCOffsetSeconds, route, progress
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        // Old queues have no routing fields. They must always remain Phone notes.
        route = try container.decodeIfPresent(TextDeliveryRoute.self, forKey: .route) ?? .phone
        captureUTCOffsetSeconds = try container.decodeIfPresent(Int.self, forKey: .captureUTCOffsetSeconds)
            ?? TimeZone.current.secondsFromGMT(for: timestamp)
        if let saved = try container.decodeIfPresent([DirectDestination: DestinationProgress].self, forKey: .progress) {
            progress = saved
        } else if case let .direct(_, destinations) = route {
            progress = Dictionary(uniqueKeysWithValues: destinations.map { ($0, DestinationProgress()) })
        } else {
            progress = [:]
        }
        try validate()
    }

    fileprivate func validate() throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 32 * 1024, (-18 * 3600...18 * 3600).contains(captureUTCOffsetSeconds),
              timestamp.timeIntervalSinceReferenceDate.isFinite else { throw DirectSendError.invalidResponse }
        switch route {
        case .phone:
            guard progress.isEmpty else { throw DirectSendError.invalidResponse }
        case let .direct(_, destinations):
            guard !destinations.isEmpty, Set(progress.keys) == destinations,
                  progress.values.allSatisfy({ $0.attempts >= 0 && $0.attempts <= 20 }) else {
                throw DirectSendError.invalidResponse
            }
        }
    }
}

/// One serialized outbox. Publish changes only after an atomic disk write succeeds.
@MainActor
@Observable
public final class TextDeliveryQueue {
    public private(set) var notes: [CapturedNote]
    private let fileURL: URL
    private let persist: @MainActor (Data, URL) throws -> Void

    public init(fileURL: URL, legacyNotesData: Data? = nil,
                persist: @escaping @MainActor (Data, URL) throws -> Void = { data, url in
                    try data.write(to: url, options: .atomic)
                }) throws {
        self.fileURL = fileURL
        self.persist = persist
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            notes = try JSONDecoder().decode([CapturedNote].self, from: Data(contentsOf: fileURL))
        } else {
            notes = try legacyNotesData.map { try JSONDecoder().decode([CapturedNote].self, from: $0) } ?? []
            try persist(JSONEncoder().encode(notes), fileURL)
        }
        guard Set(notes.map(\.id)).count == notes.count else { throw DirectSendError.invalidResponse }
    }

    public func enqueue(_ note: CapturedNote) throws {
        try note.validate()
        if notes.contains(where: { $0.id == note.id }) { return }
        try replace(notes + [note])
    }

    public func acknowledgePhone(_ id: UUID) throws {
        guard notes.contains(where: { $0.id == id && $0.route == .phone }) else { return }
        try replace(notes.filter { $0.id != id })
    }

    public func complete(_ id: UUID, destination: DirectDestination) throws {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              var state = notes[index].progress[destination], !state.delivered else { return }
        var updated = notes
        state.delivered = true
        updated[index].progress[destination] = state
        if updated[index].pendingDestinations.isEmpty { updated.remove(at: index) }
        try replace(updated)
    }

    public func recordFailure(_ id: UUID, destination: DirectDestination, now: Date = Date(), retryAfter: TimeInterval? = nil) throws {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              var state = notes[index].progress[destination], !state.delivered else { return }
        state.attempts = min(20, state.attempts + 1)
        let exponential = min(3600, 5 * pow(2, Double(state.attempts - 1)))
        let serverDelay = retryAfter.flatMap { $0.isFinite ? max(0, min($0, 86400)) : nil } ?? 0
        state.nextAttemptAt = now.addingTimeInterval(max(exponential, serverDelay))
        var updated = notes
        updated[index].progress[destination] = state
        try replace(updated)
    }

    #if DEBUG
    public func removeAllForTesting() throws { try replace([]) }
    #endif

    private func replace(_ updated: [CapturedNote]) throws {
        try persist(JSONEncoder().encode(updated), fileURL)
        notes = updated
    }
}
