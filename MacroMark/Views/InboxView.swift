import SwiftUI
import SwiftData
import MacroMarkKit

enum InboxDateFilter {
    static func notes(_ notes: [ProcessedNote], on selectedDate: Date, calendar: Calendar = .current) -> [ProcessedNote] {
        notes.filter { DaySelection.contains($0.createdAt, inSelectedDay: selectedDate, calendar: calendar) }
    }
}

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProcessedNote.createdAt, order: .reverse) private var notes: [ProcessedNote]
    @State private var selectedDate = Date()
    @State private var showingFutureComposer = false

    private var filteredNotes: [ProcessedNote] {
        InboxDateFilter.notes(notes, on: selectedDate)
    }

    private var isFutureDay: Bool {
        DaySelection.isFutureDay(selectedDate)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $selectedDate, displayedComponents: .date)
                }

                if filteredNotes.isEmpty {
                    ContentUnavailableView(
                        isFutureDay ? "No Future Notes" : "No Notes",
                        systemImage: isFutureDay ? "calendar.badge.plus" : "tray",
                        description: Text(isFutureDay ? "Create a note for this day when you want to plan ahead." : "Notes recorded for this day will appear here.")
                    )
                } else {
                    ForEach(filteredNotes) { note in
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
            .navigationTitle(selectedDate.formatted(date: .abbreviated, time: .omitted))
            .toolbar {
                if isFutureDay {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("New Note", systemImage: "square.and.pencil") {
                            showingFutureComposer = true
                        }
                    }
                }

                if !filteredNotes.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showingFutureComposer) {
                FutureNoteComposerView(selectedDate: selectedDate)
            }
        }
    }
    
    private func deleteNotes(offsets: IndexSet) {
        let notesToDelete = offsets.map { filteredNotes[$0] }
        for note in notesToDelete {
            modelContext.delete(note)
        }
        try? modelContext.save()
    }
}

#Preview {
    InboxView()
        .modelContainer(for: ProcessedNote.self, inMemory: true)
}
