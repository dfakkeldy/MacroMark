import SwiftUI
import SwiftData
import MacroMarkKit

struct InboxView: View {
    @State private var selectedDate = Date()
    @State private var showingFutureComposer = false

    private var isFutureDay: Bool {
        DaySelection.isFutureDay(selectedDate)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $selectedDate, displayedComponents: .date)
                }

                DayNotesSection(selectedDate: selectedDate, isFutureDay: isFutureDay)
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

                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showingFutureComposer) {
                FutureNoteComposerView(selectedDate: selectedDate)
            }
        }
    }
}

/// The notes for the selected day. Owns a day-scoped `@Query` so SwiftData filters
/// in the store — the inbox fetches only the selected day's notes instead of every
/// `ProcessedNote` ever captured and then filtering the full set in memory.
private struct DayNotesSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var notes: [ProcessedNote]
    private let isFutureDay: Bool

    init(selectedDate: Date, isFutureDay: Bool) {
        self.isFutureDay = isFutureDay
        let interval = DaySelection.dayInterval(for: selectedDate)
        let start = interval.start
        let end = interval.end
        _notes = Query(
            filter: #Predicate<ProcessedNote> { $0.createdAt >= start && $0.createdAt < end },
            sort: \.createdAt,
            order: .reverse
        )
    }

    var body: some View {
        if notes.isEmpty {
            ContentUnavailableView(
                isFutureDay ? "No Future Notes" : "No Notes",
                systemImage: isFutureDay ? "calendar.badge.plus" : "tray",
                description: Text(isFutureDay ? "Create a note for this day when you want to plan ahead." : "Notes recorded for this day will appear here.")
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

    private func deleteNotes(offsets: IndexSet) {
        for note in offsets.map({ notes[$0] }) {
            modelContext.delete(note)
        }
        try? modelContext.save()
    }
}

#Preview {
    InboxView()
        .modelContainer(for: ProcessedNote.self, inMemory: true)
}
