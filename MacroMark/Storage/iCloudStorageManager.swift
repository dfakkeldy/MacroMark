import Foundation

final class iCloudStorageManager {
    static let shared = iCloudStorageManager()
    
    private init() {}
    
    // Fallback to local documents directory if iCloud isn't set up yet
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
    
    func appendText(_ text: String, for date: Date = Date()) {
        let baseDir = baseDirectoryURL
        let isSecurityScoped = UserDefaults.standard.data(forKey: "customSaveBookmark") != nil
        
        if isSecurityScoped {
            _ = baseDir.startAccessingSecurityScopedResource()
        }
        
        defer {
            if isSecurityScoped {
                baseDir.stopAccessingSecurityScopedResource()
            }
        }
        
        let filename = date.formatted(Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash)) + ".md"
        let fileURL = baseDir.appendingPathComponent(filename)
        
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
    
    func readText(for date: Date = Date()) -> String? {
        let baseDir = baseDirectoryURL
        let isSecurityScoped = UserDefaults.standard.data(forKey: "customSaveBookmark") != nil
        
        if isSecurityScoped {
            _ = baseDir.startAccessingSecurityScopedResource()
        }
        
        defer {
            if isSecurityScoped {
                baseDir.stopAccessingSecurityScopedResource()
            }
        }
        
        let filename = date.formatted(Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash)) + ".md"
        let fileURL = baseDir.appendingPathComponent(filename)
        
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
