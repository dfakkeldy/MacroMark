import Foundation

/// Complete index assembled from paged responses.
public struct DailyLogFileIndex: Sendable, Equatable {
    public let paths: [String]
    public let todayPath: String?

    public init(paths: [String], todayPath: String?) {
        self.paths = paths
        self.todayPath = todayPath
    }
}

/// Single paged response for the index — phone returns a page plus truncation flag.
public struct DailyLogFileIndexPage: Sendable, Equatable {
    public let paths: [String]
    public let nextOffset: Int?
    public let todayPath: String?
    public let isTruncated: Bool

    public init(paths: [String], nextOffset: Int?, todayPath: String?, isTruncated: Bool) {
        self.paths = paths
        self.nextOffset = nextOffset
        self.todayPath = todayPath
        self.isTruncated = isTruncated
    }
}

/// Typed errors the watch UI surfaces to the user.
public enum DailyLogFetchError: Error, Sendable, Equatable {
    case unavailable
    case transportFailure
    case invalidResponse
    case tooLarge
    case invalidUTF8
    case indexTruncated

    public var message: String {
        switch self {
        case .unavailable, .transportFailure:
            "Couldn’t reach iPhone."
        case .tooLarge:
            "This file is too large for Apple Watch."
        case .indexTruncated:
            "Too many files to show."
        case .invalidResponse, .invalidUTF8:
            "Couldn’t read this file."
        }
    }
}

/// Bounded payload helpers for the WatchConnectivity daily-log protocol.
/// Chunks are raw bytes so a multi-byte UTF-8 scalar may span responses; decode
/// only after every chunk has been reassembled.
public enum DailyLogTransfer {
    /// Path page — 50 per page, up to 100.
    public static let defaultPathPageLimit = 50
    public static let maximumPathPageLimit = 100

    /// File content chunks — 32 KiB per chunk.
    public static let defaultChunkByteCount = 32 * 1024
    public static let maximumChunkByteCount = 32 * 1024

    /// Absolute ceiling: a single daily note must never exceed 512 KiB.
    public static let maximumFileByteCount = 512 * 1024

    /// Index ceiling: at most 1 000 paths / 20 pages.
    public static let maximumIndexPathCount = 1_000
    public static let maximumIndexPageCount = 20

    /// Returns a bounded prefix of the full path array, with a truncation flag.
    public static func boundedPaths(_ paths: [String]) -> (paths: [String], isTruncated: Bool) {
        let bounded = Array(paths.prefix(maximumIndexPathCount))
        return (bounded, paths.count > bounded.count)
    }

    /// Extracts a page of paths at the given offset.
    /// Returns `([], nil)` when the offset is out of range (terminal page).
    public static func page(
        _ paths: [String],
        offset: Int,
        limit: Int
    ) -> (paths: [String], nextOffset: Int?) {
        guard offset >= 0, offset < paths.count else { return ([], nil) }

        let count = min(max(limit, 1), maximumPathPageLimit)
        let end = min(offset + count, paths.count)
        return (Array(paths[offset..<end]), end < paths.count ? end : nil)
    }

    /// Extracts a byte chunk from raw file data at the given offset.
    /// Returns `(Data(), nil)` when the offset is out of range.
    public static func chunk(
        _ data: Data,
        offset: Int,
        maximumByteCount: Int
    ) -> (data: Data, nextOffset: Int?) {
        guard offset >= 0, offset < data.count else { return (Data(), nil) }

        let count = min(max(maximumByteCount, 1), maximumChunkByteCount)
        let end = min(offset + count, data.count)
        return (data.subdata(in: offset..<end), end < data.count ? end : nil)
    }
}
