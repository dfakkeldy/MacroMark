import Foundation

/// Centralized file-format constants shared across the iOS app, the watch app, and
/// MacroMarkKit — so a typo in an extension can't silently break a filename and the
/// audio/note formats have a single source of truth.
public enum StorageFormat {
    /// Extension for recorded audio notes awaiting transcription + transfer.
    public static let audioFileExtension = "m4a"

    /// Extension for the daily Markdown note files.
    public static let dailyNoteExtension = "md"
}
