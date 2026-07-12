import Foundation

public enum DailyLogFilePath {
    public static func isSafeRelativeMarkdownPath(_ path: String) -> Bool {
        guard path.lowercased().hasSuffix(".md"),
              !path.hasPrefix("/"),
              !path.contains("\\")
        else {
            return false
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }

    public static func resolvedURL(for path: String, in directory: URL) -> URL? {
        guard isSafeRelativeMarkdownPath(path) else { return nil }

        let baseDirectory = directory.standardizedFileURL
        let components = path.split(separator: "/")
        var candidate = baseDirectory

        for component in components {
            candidate = candidate.appending(path: String(component))
            guard !isSymbolicLink(candidate) else { return nil }
        }

        return candidate
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    public static func markdownFilePaths(in directory: URL) -> [String] {
        let baseDirectory = directory.standardizedFileURL
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .isHiddenKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: baseDirectory,
            includingPropertiesForKeys: Array(keys),
            options: options
        ) else {
            return []
        }

        var paths: [String] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isHidden != true,
                  values.isSymbolicLink != true
            else {
                continue
            }

            let relativePath = String(fileURL.standardizedFileURL.path.dropFirst(baseDirectory.path.count + 1))
            guard isSafeRelativeMarkdownPath(relativePath),
                  resolvedURL(for: relativePath, in: baseDirectory) != nil
            else {
                continue
            }
            paths.append(relativePath)
        }

        // Daily note filenames encode their date, so descending path order gives
        // the browser a stable newest-first default without relying on filesystem metadata.
        return paths.sorted {
            $0.localizedStandardCompare($1) == .orderedDescending
        }
    }
}
