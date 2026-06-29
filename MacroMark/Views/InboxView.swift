import SwiftUI
import SwiftData
import MacroMarkKit

enum InboxStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case exported = "Exported"
    case needsAttention = "Needs Attention"
    case unexported = "Unexported"

    var id: String { rawValue }
}

enum InboxDateFilter {
    static func notes(
        _ notes: [ProcessedNote],
        on selectedDate: Date,
        status: InboxStatusFilter = .all,
        calendar: Calendar = .current
    ) -> [ProcessedNote] {
        notes.filter { note in
            guard DaySelection.contains(note.createdAt, inSelectedDay: selectedDate, calendar: calendar) else {
                return false
            }
            switch status {
            case .all:
                return true
            case .exported:
                return note.exportStatus == .exported
            case .needsAttention:
                return note.exportStatus.needsAttention
            case .unexported:
                return note.exportStatus != .exported
            }
        }
    }
}

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var navigation
    @Query(sort: \ProcessedNote.createdAt, order: .reverse) private var notes: [ProcessedNote]
    @State private var statusFilter: InboxStatusFilter = .all
    @State private var screenshotNotes: [ProcessedNote] = []

    private var selectedDate: Date {
        get { navigation.selectedDate }
        nonmutating set { navigation.selectedDate = newValue }
    }

    private var filteredNotes: [ProcessedNote] {
        InboxDateFilter.notes(displayedNotes, on: selectedDate, status: statusFilter)
    }

    private var displayedNotes: [ProcessedNote] {
        guard ScreenshotMode.isEnabled else {
            return notes
        }
        if !screenshotNotes.isEmpty {
            return screenshotNotes
        }
        return notes.isEmpty ? ScreenshotMode.previewNotes : notes
    }

    private var isFutureDay: Bool {
        DaySelection.isFutureDay(selectedDate)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker(
                        "Day",
                        selection: Binding(
                            get: { navigation.selectedDate },
                            set: { navigation.selectedDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .accessibilityIdentifier("inbox.datePicker")
                }

                Section {
                    Picker("Status", selection: $statusFilter) {
                        ForEach(InboxStatusFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
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
                                    Label(note.exportStatus.displayName, systemImage: note.exportStatus.systemImage)
                                        .foregroundStyle(note.exportStatus == .exported ? .green : (note.exportStatus.needsAttention ? .orange : .secondary))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("note.row")
                    }
                    .onDelete(perform: deleteNotes)
                }
            }
            .accessibilityIdentifier("inbox.list")
            .onAppear {
                ScreenshotMode.seedIfNeeded(in: modelContext)
                loadScreenshotNotesIfNeeded()
            }
            .navigationTitle(selectedDate.formatted(date: .abbreviated, time: .omitted))
            .toolbar {
                if isFutureDay {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("New Note", systemImage: "square.and.pencil") {
                            navigation.openCaptureComposer(date: selectedDate, mode: .future)
                        }
                    }
                }

                if !filteredNotes.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
            .sheet(
                item: Binding(
                    get: { navigation.composerRequest },
                    set: { newValue in
                        if newValue == nil {
                            navigation.clearComposerRequest()
                        } else {
                            navigation.composerRequest = newValue
                        }
                    }
                )
            ) { request in
                FutureNoteComposerView(selectedDate: request.date, mode: request.mode)
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

    private func loadScreenshotNotesIfNeeded() {
        guard ScreenshotMode.isEnabled else { return }

        var descriptor = FetchDescriptor<ProcessedNote>(
            sortBy: [SortDescriptor(\ProcessedNote.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 10
        let fetchedNotes = (try? modelContext.fetch(descriptor)) ?? []
        screenshotNotes = fetchedNotes.isEmpty ? ScreenshotMode.previewNotes : fetchedNotes
    }
}

#Preview {
    InboxView()
        .environment(AppNavigation())
        .modelContainer(for: ProcessedNote.self, inMemory: true)
}
