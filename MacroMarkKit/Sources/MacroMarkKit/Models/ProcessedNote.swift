import Foundation
import SwiftData

@Model
public final class ProcessedNote {
    public var text: String = ""
    public var createdAt: Date = Date()
    public var isExported: Bool = false
    public var exportTarget: String? = nil
    public var transcriptionPartial: Bool = false
    public var exportStatusRaw: String = ExportStatus.pending.rawValue
    public var exportStatusMessage: String = ""
    public var lastExportAttemptAt: Date?
    public var lastExportedAt: Date?

    public var exportStatus: ExportStatus {
        get { ExportStatus(rawValue: exportStatusRaw) ?? (isExported ? .exported : .pending) }
        set { exportStatusRaw = newValue.rawValue }
    }

    public init(
        text: String,
        createdAt: Date = Date(),
        isExported: Bool = false,
        exportTarget: String? = nil,
        transcriptionPartial: Bool = false,
        exportStatus: ExportStatus = .pending,
        exportStatusMessage: String = "",
        lastExportAttemptAt: Date? = nil,
        lastExportedAt: Date? = nil
    ) {
        self.text = text
        self.createdAt = createdAt
        self.isExported = isExported
        self.exportTarget = exportTarget
        self.transcriptionPartial = transcriptionPartial
        self.exportStatusRaw = isExported ? ExportStatus.exported.rawValue : exportStatus.rawValue
        self.exportStatusMessage = exportStatusMessage
        self.lastExportAttemptAt = lastExportAttemptAt
        self.lastExportedAt = lastExportedAt
    }
}
