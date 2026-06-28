import Foundation
import os

/// Outcome of an append attempt. The caller must treat `.deferred` and `.failed`
/// as "not yet delivered" and keep the note in its write-ahead log for retry —
/// the user's definition of "delivered" is "in the daily-note file," not "saved
/// to SwiftData."
public enum AppendResult {
    /// The text was appended (or a new file created) successfully.
    case appended
    /// The day's file exists in iCloud but is not materialized locally; the write
    /// was skipped to avoid clobbering it. Retryable.
    case deferred
    /// The write failed (I/O error, coordinator error). Retryable.
    case failed
}

@MainActor
public final class iCloudStorageManager {
    public nonisolated static let shared = iCloudStorageManager()

    /// Published so UI can observe when iCloud is unavailable and data is saving locally.
    public private(set) var isUsingFallbackStorage = false

    nonisolated private init() {}

    nonisolated private var folderSettings: FolderSettings {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.folderSettings.rawValue),
              let settings = try? JSONDecoder().decode(FolderSettings.self, from: data) else {
            return FolderSettings()
        }
        return settings
    }

    nonisolated private var dailyNoteFormatting: DailyNoteFormatting {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.dailyNoteFormatting.rawValue),
              let formatting = try? JSONDecoder().decode(DailyNoteFormatting.self, from: data) else {
            return DailyNoteFormatting()
        }
        return formatting
    }

    /// Resolve the base directory without touching main-actor state. Returns the
    /// URL plus the value the write path should publish to `isUsingFallbackStorage`
    /// (`nil` means "leave the flag unchanged", as when a custom save location is
    /// in use). Being `nonisolated` lets the read path run off the main actor.
    nonisolated private func resolvedBaseDirectory() -> (url: URL, fallback: Bool?) {
        if let bookmarkData = UserDefaults.standard.data(forKey: UserDefaultsKey.customSaveBookmark.rawValue) {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale {
                    // Stale bookmark — the user moved the folder. Clear it so we fall back to iCloud.
                    UserDefaults.standard.removeObject(forKey: UserDefaultsKey.customSaveBookmark.rawValue)
                    // Fall through to iCloud / local fallback below.
                } else {
                    return (url, nil)
                }
            }
        }

        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let documentsDir = containerURL.appendingPathComponent("Documents")
            if !FileManager.default.fileExists(atPath: documentsDir.path) {
                try? FileManager.default.createDirectory(at: documentsDir, withIntermediateDirectories: true)
            }
            return (documentsDir, false)
        }
        return (URL.documentsDirectory, true)
    }

    /// Main-actor write-path accessor: resolves the base directory and publishes
    /// the `isUsingFallbackStorage` flag for the UI. The read path uses
    /// `resolvedBaseDirectory()` directly and does not mutate the flag.
    private var baseDirectoryURL: URL {
        let (url, fallback) = resolvedBaseDirectory()
        if let fallback {
            isUsingFallbackStorage = fallback
        }
        return url
    }

    nonisolated private func fileURL(for date: Date, settings: FolderSettings, base: URL) -> URL {
        let filename = settings.format(date: date) + ".md"

        switch settings.structure {
        case .flat:
            return base.appending(path: filename)

        case .monthly:
            let month = date.formatted(Date.FormatStyle().month(.twoDigits))
            let year = date.formatted(Date.FormatStyle().year())
            let folder = "\(year)-\(month)"
            let dir = base.appending(path: folder)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appending(path: filename)

        case .yearlyMonthly:
            let year = date.formatted(Date.FormatStyle().year())
            let month = date.formatted(Date.FormatStyle().month(.twoDigits))
            let dir = base.appending(path: year).appending(path: month)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appending(path: filename)
        }
    }

    @discardableResult
    public func appendText(_ text: String, for date: Date = Date()) async -> AppendResult {
        let baseDir = baseDirectoryURL
        let isSecurityScoped = UserDefaults.standard.data(forKey: UserDefaultsKey.customSaveBookmark.rawValue) != nil
        let settings = folderSettings

        if isSecurityScoped {
            _ = baseDir.startAccessingSecurityScopedResource()
        }

        defer {
            if isSecurityScoped {
                baseDir.stopAccessingSecurityScopedResource()
            }
        }

        let fileURL = self.fileURL(for: date, settings: settings, base: baseDir)

        // If the day's file already exists in iCloud but hasn't been downloaded
        // to this device yet, FileManager.fileExists returns false — which would
        // otherwise make us OVERWRITE the whole file with just this one entry,
        // wiping every earlier note for the day. Materialize it first.
        await ensureDownloaded(fileURL)

        let textToAppend = DailyNoteFormatter.renderEntry(
            text: text,
            timestamp: date,
            formatting: dailyNoteFormatting
        )
        guard let dataToAppend = textToAppend.data(using: .utf8) else { return .failed }

        // Tracks whether the un-materialized-placeholder branch fired so we can
        // report `.deferred` distinctly from a real I/O `.failed`.
        var deferred = false
        var writeSucceeded = false
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forMerging, error: &error) { url in
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let fileHandle = try FileHandle(forWritingTo: url)
                    defer { fileHandle.closeFile() }
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(dataToAppend)
                    writeSucceeded = true
                } catch {
                    Logger.storage.error("Failed to append to existing file: \(error.localizedDescription, privacy: .public)")
                }
            } else if cloudCopyExistsButNotDownloaded(url) {
                // The file exists remotely but still isn't local. Refuse to write
                // (which would clobber it). Report `.deferred` so the caller keeps
                // the note in its write-ahead log and retries once iCloud
                // materializes the file.
                deferred = true
                Logger.storage.info("iCloud file not yet downloaded — deferring append to avoid overwrite")
            } else {
                do {
                    try dataToAppend.write(to: url)
                    writeSucceeded = true
                } catch {
                    Logger.storage.error("Failed to write to new file: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        if let error {
            Logger.storage.error("File coordinator error: \(error.localizedDescription, privacy: .public)")
        }
        if writeSucceeded { return .appended }
        if deferred { return .deferred }
        return .failed
    }

    /// iCloud stores not-yet-downloaded files as a hidden `.<name>.icloud` placeholder.
    private func cloudPlaceholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent("." + url.lastPathComponent + ".icloud")
    }

    private func cloudCopyExistsButNotDownloaded(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: cloudPlaceholderURL(for: url).path)
    }

    /// If the file exists in iCloud but isn't materialized locally, trigger a
    /// download and wait briefly for it so an append doesn't overwrite it.
    /// Uses cooperative `Task.sleep` so it never blocks the MainActor.
    private func ensureDownloaded(_ url: URL) async {
        guard !FileManager.default.fileExists(atPath: url.path),
              cloudCopyExistsButNotDownloaded(url) else { return }

        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        // Bounded wait (~2s). If it doesn't arrive we fall through to the
        // deferral branch in appendText rather than risk clobbering.
        for _ in 0..<20 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    nonisolated public func readText(for date: Date = Date()) -> String? {
        let baseDir = resolvedBaseDirectory().url
        let isSecurityScoped = UserDefaults.standard.data(forKey: UserDefaultsKey.customSaveBookmark.rawValue) != nil
        let settings = folderSettings

        if isSecurityScoped {
            _ = baseDir.startAccessingSecurityScopedResource()
        }

        defer {
            if isSecurityScoped {
                baseDir.stopAccessingSecurityScopedResource()
            }
        }

        let fileURL = self.fileURL(for: date, settings: settings, base: baseDir)

        var fileContent: String?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &error) { url in
            fileContent = try? String(contentsOf: url, encoding: .utf8)
        }
        if let error {
            Logger.storage.error("File coordinator read error: \(error.localizedDescription, privacy: .public)")
        }

        return fileContent
    }
}
