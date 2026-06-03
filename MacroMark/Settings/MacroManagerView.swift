import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Speech

struct MacroManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Macro.createdAt) private var macros: [Macro]
    
    @AppStorage("captureMode") private var captureMode: String = "audio"
    @AppStorage("customSaveBookmark") private var customSaveBookmark: Data?
    @State private var isShowingAddSheet = false
    @State private var showingFolderPicker = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Settings") {
                    Picker("Watch Capture Mode", selection: $captureMode) {
                        Text("Instant (Audio)").tag("audio")
                        Text("Standard (Dictation)").tag("system")
                    }
                    .onChange(of: captureMode) { _, newValue in
                        WatchConnectivityProvider.shared.updateSettings(captureMode: newValue)
                    }
                }
                
                Section("Storage Location") {
                    Button(customSaveBookmark == nil ? "Choose Save Location..." : "Change Save Location...") {
                        showingFolderPicker = true
                    }
                    if customSaveBookmark != nil {
                        Button("Reset to Default (iCloud)", role: .destructive) {
                            customSaveBookmark = nil
                        }
                    }
                }
                
                Section("Macros") {
                    ForEach(macros) { macro in
                    HStack {
                        Text(macro.trigger)
                            .fontWeight(.medium)
                        Spacer()
                        Text(macro.replacement)
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                    }
                    .onDelete(perform: deleteMacros)
                }
            }
            .navigationTitle("MacroMark")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") {
                        isShowingAddSheet = true
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $isShowingAddSheet) {
                NavigationStack {
                    AddMacroView()
                }
            }
            .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    if let bookmark = try? url.bookmarkData() {
                        customSaveBookmark = bookmark
                    }
                case .failure(let error):
                    print("Error selecting folder: \(error)")
                }
            }
            .onAppear {
                SFSpeechRecognizer.requestAuthorization { _ in }
                prepopulateIfNeeded()
            }
        }
    }
    
    private func deleteMacros(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(macros[index])
        }
    }
    
    private func prepopulateIfNeeded() {
        if macros.isEmpty {
            let defaults = [
                // Markdown Headings
                Macro(trigger: "Heading One", replacement: "# "),
                Macro(trigger: "Heading Two", replacement: "## "),
                Macro(trigger: "Heading Three", replacement: "### "),
                Macro(trigger: "Heading Four", replacement: "#### "),
                Macro(trigger: "Heading Five", replacement: "##### "),
                Macro(trigger: "Heading Six", replacement: "###### "),
                
                // Markdown Formatting
                Macro(trigger: "Bold", replacement: "**"),
                Macro(trigger: "Italic", replacement: "_"),
                Macro(trigger: "Strikethrough", replacement: "~~"),
                Macro(trigger: "Code Block", replacement: "```"),
                Macro(trigger: "Inline Code", replacement: "`"),
                Macro(trigger: "Quote", replacement: "> "),
                
                // Markdown Lists
                Macro(trigger: "Bullet", replacement: "- "),
                Macro(trigger: "Numbered", replacement: "1. "),
                Macro(trigger: "Task", replacement: "- [ ] "),
                
                // Clever Macros
                Macro(trigger: "Timestamp", replacement: "{time} - "),
                Macro(trigger: "New Journal Entry", replacement: "{newline}{newline}## {date} at {time}{newline}"),
                Macro(trigger: "Horizontal Rule", replacement: "---{newline}"),
                Macro(trigger: "Paste", replacement: "{clipboard}"),
                Macro(trigger: "Dropoff", replacement: "{location} - "),
                Macro(trigger: "Smile", replacement: "😀"),
                Macro(trigger: "Block ID", replacement: "^id-{uuid}")
            ]
            
            for macro in defaults {
                modelContext.insert(macro)
            }
        }
    }
}

struct AddMacroView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var trigger: String = ""
    @State private var replacement: String = ""
    
    var body: some View {
        Form {
            Section("Trigger (What you say)") {
                TextField("e.g., Heading One", text: $trigger)
            }
            Section("Replacement (What it outputs)") {
                TextField("e.g., # ", text: $replacement)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .navigationTitle("New Macro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let newMacro = Macro(trigger: trigger, replacement: replacement)
                    modelContext.insert(newMacro)
                    dismiss()
                }
                .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || replacement.isEmpty)
            }
        }
    }
}

#Preview {
    MacroManagerView()
        .modelContainer(for: Macro.self, inMemory: true)
}
