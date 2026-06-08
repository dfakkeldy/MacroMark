import Foundation

@MainActor
public final class iCloudStorageManager {
    public static let shared = iCloudStorageManager()

    /// Published so UI can observe when iCloud is unavailable and data is saving locally.
    public private(set) var isUsingFallbackStorage = false

    private init() {}

    private var folderSettings: FolderSettings {
        guard let data = UserDefaults.standard.data(forKey: "folderSettings"),
              let settings = try? JSONDecoder().decode(FolderSettings.self, from: data) else {
            return FolderSettings()
        }
        return settings
    }

    private var baseDirectoryURL: URL {
        if let bookmarkData = UserDefaults.standard.data(forKey: "customSaveBookmark") {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                if isStale {
                    // Stale bookmark — the user moved the folder. Clear it so we fall back to iCloud.
                    UserDefaults.standard.removeObject(forKey: "customSaveBookmark")
                    // Fall through to iCloud / local fallback below.
                } else {
                    return url
                }
            }
        }

        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let documentsDir = containerURL.appendingPathComponent("Documents")
            if !FileManager.default.fileExists(atPath: documentsDir.path) {
                try? FileManager.default.createDirectory(at: documentsDir, withIntermediateDirectories: true)
            }
            isUsingFallbackStorage = false
            return documentsDir
        }
        isUsingFallbackStorage = true
        return URL.documentsDirectory
    }

    private func fileURL(for date: Date, settings: FolderSettings) -> URL {
        let filename = settings.format(date: date) + ".md"

        switch settings.structure {
        case .flat:
            return baseDirectoryURL.appending(path: filename)

        case .monthly:
            let month = date.formatted(Date.FormatStyle().month(.twoDigits))
            let year = date.formatted(Date.FormatStyle().year())
            let folder = "\(year)-\(month)"
            let dir = baseDirectoryURL.appending(path: folder)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appending(path: filename)

        case .yearlyMonthly:
            let year = date.formatted(Date.FormatStyle().year())
            let month = date.formatted(Date.FormatStyle().month(.twoDigits))
            let dir = baseDirectoryURL.appending(path: year).appending(path: month)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appending(path: filename)
        }
    }

    @discardableResult
    public func appendText(_ text: String, for date: Date = Date()) -> Bool {
        let baseDir = baseDirectoryURL
        let isSecurityScoped = UserDefaults.standard.data(forKey: "customSaveBookmark") != nil
        let settings = folderSettings

        if isSecurityScoped {
            _ = baseDir.startAccessingSecurityScopedResource()
        }

        defer {
            if isSecurityScoped {
                baseDir.stopAccessingSecurityScopedResource()
            }
        }

        let fileURL = self.fileURL(for: date, settings: settings)

        // If the day's file already exists in iCloud but hasn't been downloaded
        // to this device yet, FileManager.fileExists returns false — which would
        // otherwise make us OVERWRITE the whole file with just this one entry,
        // wiping every earlier note for the day. Materialize it first.
        ensureDownloaded(fileURL)

        let timeString = date.formatted(date: .omitted, time: .shortened)
        let textToAppend = "\n\n\(timeString)\n\n\(text)\n\n"
        guard let dataToAppend = textToAppend.data(using: .utf8) else { return false }

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
                    print("Failed to append to existing file: \(error)")
                }
            } else if cloudCopyExistsButNotDownloaded(url) {
                // The file exists remotely but still isn't local. Refuse to write
                // (which would clobber it). The note is already safe in SwiftData;
                // it will be appended on a later call once the file has downloaded.
                print("iCloud file not yet downloaded — deferring append to avoid overwrite")
            } else {
                do {
                    try dataToAppend.write(to: url)
                    writeSucceeded = true
                } catch {
                    print("Failed to write to new file: \(error)")
                }
            }
        }
        if let error {
            print("File coordinator error: \(error)")
        }
        return writeSucceeded
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
    private func ensureDownloaded(_ url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path),
              cloudCopyExistsButNotDownloaded(url) else { return }

        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        // Bounded wait (~2s). If it doesn't arrive we fall through to the
        // deferral branch in appendText rather than risk clobbering.
        for _ in 0..<20 {
            if FileManager.default.fileExists(atPath: url.path) { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    public func readText(for date: Date = Date()) -> String? {
        let baseDir = baseDirectoryURL
        let isSecurityScoped = UserDefaults.standard.data(forKey: "customSaveBookmark") != nil
        let settings = folderSettings

        if isSecurityScoped {
            _ = baseDir.startAccessingSecurityScopedResource()
        }

        defer {
            if isSecurityScoped {
                baseDir.stopAccessingSecurityScopedResource()
            }
        }

        let fileURL = self.fileURL(for: date, settings: settings)

        var fileContent: String?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &error) { url in
            fileContent = try? String(contentsOf: url, encoding: .utf8)
        }
        if let error {
            print("File coordinator read error: \(error)")
        }

        return fileContent
    }
}
