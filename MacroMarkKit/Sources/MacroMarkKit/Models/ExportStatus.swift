import Foundation

public enum ExportStatus: String, Codable, CaseIterable {
    case pending
    case processing
    case exported
    case deferred
    case failed
    case noTarget

    public var displayName: String {
        switch self {
        case .pending: "Pending"
        case .processing: "Processing"
        case .exported: "Exported"
        case .deferred: "Deferred, retrying"
        case .failed: "Needs attention"
        case .noTarget: "Saved in inbox"
        }
    }

    public var systemImage: String {
        switch self {
        case .pending: "clock"
        case .processing: "arrow.triangle.2.circlepath"
        case .exported: "checkmark.circle.fill"
        case .deferred: "icloud.and.arrow.up"
        case .failed: "exclamationmark.triangle.fill"
        case .noTarget: "tray.fill"
        }
    }

    public var needsAttention: Bool {
        self == .deferred || self == .failed
    }
}
