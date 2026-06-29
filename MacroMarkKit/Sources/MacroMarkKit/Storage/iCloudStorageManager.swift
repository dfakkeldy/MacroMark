import Foundation
import os

/// Outcome of an append attempt. The caller must treat `.deferred` and `.failed`
/// as "not yet delivered" and keep the note in its write-ahead log for retry —
/// the user's definition of "delivered" is "in the daily-note file," not "saved
/// to SwiftData."
public enum AppendResult: Sendable {
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

    nonisolated private static func fileURL(
        for date: Date,
        settings: FolderSettings,
        base: URL,
        createDirectories: Bool
    ) -> URL {
        let url = appending(relativePath: settings.relativePath(for: date), to: base)
        if createDirectories {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        return url
    }

    nonisolated private static func appending(relativePath: String, to base: URL) -> URL {
        relativePath.split(separator: "/").reduce(base) { url, component in
            url.appending(path: String(component))
        }
    }

    @discardableResult
    public func appendText(_ text: String, for date: Date = Date()) async -> AppendResult {
        let resolvedDirectory = resolvedBaseDirectory()
        let baseDir = resolvedDirectory.url
        let isFallbackStorage = resolvedDirectory.fallback == true
        if let fallback = resolvedDirectory.fallback {
            isUsingFallbackStorage = fallback
        }

        let isSecurityScoped = UserDefaults.standard.data(forKey: UserDefaultsKey.customSaveBookmark.rawValue) != nil
        let settings = folderSettings
        let formatting = dailyNoteFormatting

        return await Task.detached(priority: .utility) {
            await Self.appendTextOffMain(
                text,
                for: date,
                baseDir: baseDir,
                isFallbackStorage: isFallbackStorage,
                isSecurityScoped: isSecurityScoped,
                settings: settings,
                formatting: formatting
            )
        }.value
    }

    nonisolated private static func appendTextOffMain(
        _ text: String,
        for date: Date,
        baseDir: URL,
        isFallbackStorage: Bool,
        isSecurityScoped: Bool,
        settings: FolderSettings,
        formatting: DailyNoteFormatting
    ) async -> AppendResult {
        var didStartSecurityScope = false
        if isSecurityScoped {
            guard baseDir.startAccessingSecurityScopedResource() else {
                Logger.storage.error("Could not access the selected export folder security scope")
                return .failed
            }
            didStartSecurityScope = true
        }

        defer {
            if didStartSecurityScope {
                baseDir.stopAccessingSecurityScopedResource()
            }
        }

        let fileURL = Self.fileURL(for: date, settings: settings, base: baseDir, createDirectories: true)

        // If the day's file already exists in iCloud but hasn't been downloaded
        // to this device yet, FileManager.fileExists returns false — which would
        // otherwise make us OVERWRITE the whole file with just this one entry,
        // wiping every earlier note for the day. Materialize it first.
        await ensureDownloaded(fileURL)

        let textToAppend = DailyNoteFormatter.renderEntry(
            text: text,
            timestamp: date,
            formatting: formatting
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
        if writeSucceeded {
            if !isFallbackStorage {
                UserDefaults.standard.set(fileURL.path, forKey: UserDefaultsKey.lastSuccessfulExportPath.rawValue)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UserDefaultsKey.lastSuccessfulExportAt.rawValue)
            }
            return .appended
        }
        if deferred { return .deferred }
        return .failed
    }

    /// iCloud stores not-yet-downloaded files as a hidden `.<name>.icloud` placeholder.
    nonisolated private static func cloudPlaceholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent("." + url.lastPathComponent + ".icloud")
    }

    nonisolated private static func cloudCopyExistsButNotDownloaded(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: cloudPlaceholderURL(for: url).path)
    }

    /// If the file exists in iCloud but isn't materialized locally, trigger a
    /// download and wait briefly for it so an append doesn't overwrite it.
    /// Uses cooperative `Task.sleep` so it never blocks the MainActor.
    nonisolated private static func ensureDownloaded(_ url: URL) async {
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

        var didStartSecurityScope = false
        if isSecurityScoped {
            guard baseDir.startAccessingSecurityScopedResource() else {
                Logger.storage.error("Could not access the selected read folder security scope")
                return nil
            }
            didStartSecurityScope = true
        }

        defer {
            if didStartSecurityScope {
                baseDir.stopAccessingSecurityScopedResource()
            }
        }

        let fileURL = Self.fileURL(for: date, settings: settings, base: baseDir, createDirectories: false)

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
