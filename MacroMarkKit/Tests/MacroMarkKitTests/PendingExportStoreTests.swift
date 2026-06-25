import Foundation
import Testing
@testable import MacroMarkKit

struct PendingExportStoreTests {
    @Test
    func storeRoundTripsManualPendingExport() throws {
        let suiteName = "PendingExportStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let timestamp = Date(timeIntervalSince1970: 1_782_345_600)
        let entry = PendingExportEntry(
            processedText: "future note",
            timestamp: timestamp,
            isAudio: false,
            requiresWatchAcknowledgement: false
        )

        PendingExportStore.upsert(entry, userDefaults: defaults)

        #expect(PendingExportStore.read(userDefaults: defaults)[entry.noteId] == entry)
        #expect(PendingExportStore.firstEntry(processedText: "future note", timestamp: timestamp, userDefaults: defaults) == entry)

        PendingExportStore.removeMatching(processedText: "future note", timestamp: timestamp, userDefaults: defaults)

        #expect(PendingExportStore.read(userDefaults: defaults).isEmpty)
    }

    @Test
    func legacyPendingExportsDefaultToWatchAcknowledgement() throws {
        let decoder = JSONDecoder()
        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_782_345_600)
        let legacyJSON = """
        {
          "noteId": "\(id.uuidString)",
          "processedText": "watch note",
          "timestamp": \(timestamp.timeIntervalSince1970),
          "isAudio": true
        }
        """

        let entry = try decoder.decode(PendingExportEntry.self, from: try #require(legacyJSON.data(using: .utf8)))

        #expect(entry.noteId == id)
        #expect(entry.processedText == "watch note")
        #expect(entry.isAudio)
        #expect(entry.requiresWatchAcknowledgement)
    }
}
