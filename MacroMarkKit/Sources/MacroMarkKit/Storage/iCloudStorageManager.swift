import Foundation

public final class iCloudStorageManager {
    public static let shared = iCloudStorageManager()

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
                return url
            }
        }

        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let documentsDir = containerURL.appendingPathComponent("Documents")
            if !FileManager.default.fileExists(atPath: documentsDir.path) {
                try? FileManager.default.createDirectory(at: documentsDir, withIntermediateDirectories: true)
            }
            return documentsDir
        }
        return URL.documentsDirectory
    }

    private func fileURL(for date: Date, settings: FolderSettings) -> URL {
        let dateString = date.formatted(
            Date.ISO8601FormatStyle(timeZone: .current)
                .year().month().day()
                .dateSeparator(.dash)
        )

        // For custom date formats, build a simple formatter
        let filename: String
        if settings.dateFormat == "yyyy-MM-dd" {
            filename = "\(dateString).md"
        } else {
            filename = formatDate(date, format: settings.dateFormat) + ".md"
        }

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

    private func formatDate(_ date: Date, format: String) -> String {
        // Simple date format mapping using Calendar components
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
        }

        let yearStr = String(year)
        let monthStr = String(format: "%02d", month)
        let dayStr = String(format: "%02d", day)

        var result = format
        result = result.replacing("yyyy", with: yearStr)
        result = result.replacing("yy", with: String(year % 100))
        result = result.replacing("MM", with: monthStr)
        result = result.replacing("dd", with: dayStr)

        return result
    }

    public func appendText(_ text: String, for date: Date = Date()) {
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

        let timeString = date.formatted(date: .omitted, time: .shortened)
        let textToAppend = "\n\n\(timeString)\n\n\(text)\n\n"
        guard let dataToAppend = textToAppend.data(using: .utf8) else { return }

        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forMerging, error: &error) { url in
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let fileHandle = try FileHandle(forWritingTo: url)
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(dataToAppend)
                    fileHandle.closeFile()
                } catch {
                    print("Failed to append to existing file: \(error)")
                }
            } else {
                do {
                    try dataToAppend.write(to: url)
                } catch {
                    print("Failed to write to new file: \(error)")
                }
            }
        }
        if let error {
            print("File coordinator error: \(error)")
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
