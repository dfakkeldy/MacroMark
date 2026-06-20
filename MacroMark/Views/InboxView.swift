import SwiftUI
import SwiftData
import MacroMarkKit

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProcessedNote.createdAt, order: .reverse) private var notes: [ProcessedNote]
    
    var body: some View {
        NavigationStack {
            List {
                if notes.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "tray",
                        description: Text("Notes recorded on your Apple Watch will appear here.")
                    )
                } else {
                    ForEach(notes) { note in
                        NavigationLink(destination: NoteDetailView(note: note)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(note.text)
                                    .lineLimit(3)
                                    .font(.body)
                                
                                HStack {
                                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    Spacer()
                                    if note.transcriptionPartial {
                                        Label("Incomplete", systemImage: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.yellow)
                                    }
                                    if note.isExported {
                                        Label(note.exportTarget ?? "Exported", systemImage: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: deleteNotes)
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                if !notes.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
        }
    }
    
    private func deleteNotes(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(notes[index])
        }
    }
}

#Preview {
    InboxView()
        .modelContainer(for: ProcessedNote.self, inMemory: true)
}
