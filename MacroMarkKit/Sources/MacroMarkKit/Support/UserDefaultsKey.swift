import Foundation

/// Centralized `UserDefaults` / `@AppStorage` keys shared across the iOS app,
/// the watch app, and MacroMarkKit. Using these cases instead of raw string
/// literals gives compile-time checking and autocompletion — a typo in a key
/// previously degraded functionality silently with no compiler help.
///
/// For `@AppStorage`, pass `.rawValue`:
///   `@AppStorage(UserDefaultsKey.captureMode.rawValue) private var captureMode`
public enum UserDefaultsKey: String {
    // User-configurable settings (cross-target).
    case captureMode = "captureMode"
    case folderSettings = "folderSettings"
    case customSaveBookmark = "customSaveBookmark"
    case autoExportEnabled = "autoExportEnabled"
    case defaultExportTarget = "defaultExportTarget"

    // iOS-side cache.
    case cachedDailyLog = "cachedDailyLog"

    // iOS write-ahead log / dedup state.
    case processedNoteIDs = "MacroMark_ProcessedNoteIDs"
    case pendingProcessing = "MacroMark_PendingProcessing"
    case pendingAudioIn = "MacroMark_PendingAudioIn"
    case pendingExports = "MacroMark_PendingExports"

    // Watch write-ahead log / queue state.
    case pendingNotes = "MacroMark_PendingNotes"
    case queuedNoteIDs = "MacroMark_QueuedNoteIDs"
    case pendingAudio = "MacroMark_PendingAudio"
    case queuedAudioIDs = "MacroMark_QueuedAudioIDs"
}
