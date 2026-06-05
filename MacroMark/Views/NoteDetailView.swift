import SwiftUI
import SwiftData
import MacroMarkKit

struct NoteDetailView: View {
    @Bindable var note: ProcessedNote
    
    var body: some View {
        Form {
            Section {
                TextEditor(text: $note.text)
                    .frame(minHeight: 200)
                    .font(.body)
            } header: {
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            
            Section("Export") {
                ForEach(ExportTarget.allCases) { target in
                    if target == .shareSheet {
                        ShareLink(item: note.text) {
                            Label(target.rawValue, systemImage: target.iconName)
                        }
                    } else if target == .iCloud {
                        Button {
                            exportToICloud()
                        } label: {
                            Label(target.rawValue, systemImage: target.iconName)
                        }
                    } else {
                        Button {
                            exportTo(target: target)
                        } label: {
                            Label(target.rawValue, systemImage: target.iconName)
                        }
                    }
                }
            }
        }
        .navigationTitle("Note Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func exportTo(target: ExportTarget) {
        if let url = ExportManager.url(for: note, to: target) {
            UIApplication.shared.open(url) { success in
                if success {
                    note.isExported = true
                    note.exportTarget = target.rawValue
                }
            }
        }
    }
    
    private func exportToICloud() {
        // Appends to the default iCloud location as before
        Task {
            // Because iCloudStorageManager is part of the main app, we can just use NotificationCenter or a static closure if we don't have direct access.
            // Wait, iCloudStorageManager is in the iOS app target, not MacroMarkKit. We can use it directly here!
            iCloudStorageManager.shared.appendText(note.text + "\n\n")
            
            // Just updating state for UI
            await MainActor.run {
                note.isExported = true
                note.exportTarget = ExportTarget.iCloud.rawValue
            }
        }
    }
}
