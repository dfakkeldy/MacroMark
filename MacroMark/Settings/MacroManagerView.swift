import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Speech
import MacroMarkKit

struct MacroManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Macro.sortOrder, order: .forward) private var macros: [Macro]

    @AppStorage("captureMode") private var captureMode: String = "audio"
    @AppStorage("customSaveBookmark") private var customSaveBookmark: Data?
    @State private var isShowingAddSheet = false
    @State private var showingFolderPicker = false
    @State private var editingMacro: Macro?
    @State private var showingPaywall = false
    @State private var showingFolderSettings = false
    @State private var paywallReason: PaywallReason = .addMacro

    @Environment(EntitlementManager.self) private var entitlements

    enum PaywallReason: String {
        case addMacro = "Add More Macros"
        case editDefault = "Customize Defaults"
        case folderSettings = "Folder Structure"
    }

    private var customMacroCount: Int {
        macros.filter { !$0.isDefault }.count
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Settings
                Section("Settings") {
                    Picker("Watch Double Tap Action", selection: $captureMode) {
                        Text("Instant (Audio)").tag("audio")
                        Text("Standard (Dictation)").tag("system")
                    }
                    .onChange(of: captureMode) { _, newValue in
                        WatchConnectivityProvider.shared.updateSettings(captureMode: newValue)
                    }
                }

                // MARK: Storage Location
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

                // MARK: Folder Structure (Paid)
                Section {
                    Button {
                        if entitlements.canCustomizeFolderStructure {
                            showingFolderSettings = true
                        } else {
                            paywallReason = .folderSettings
                            showingPaywall = true
                        }
                    } label: {
                        HStack {
                            Text("Folder Structure")
                            Spacer()
                            if !entitlements.canCustomizeFolderStructure {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.small)
                            }
                        }
                    }
                }

                // MARK: Macros
                Section {
                    ForEach(macros) { macro in
                        Button {
                            if macro.isDefault && !entitlements.canEditDefaultMacros {
                                paywallReason = .editDefault
                                showingPaywall = true
                            } else {
                                editingMacro = macro
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(macro.trigger)
                                        .fontWeight(.medium)
                                    Text(macro.replacement)
                                        .foregroundStyle(.secondary)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                }
                                Spacer()
                                if macro.isDefault {
                                    Image(systemName: macro.isDefaultEdited ? "pencil.circle.fill" : "lock.circle")
                                        .foregroundStyle(.secondary)
                                        .imageScale(.small)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteMacros)
                    .onMove(perform: moveMacros)
                } header: {
                    HStack {
                        Text("Macros")
                        Spacer()
                        Text("\(customMacroCount)" + (entitlements.isSubscribed ? "" : "/3 free"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Restore Default Macros", role: .destructive) {
                        restoreDefaults()
                    }
                }
            }
            .navigationTitle("MacroMark")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") {
                        if !entitlements.isSubscribed && customMacroCount >= 3 {
                            paywallReason = .addMacro
                            showingPaywall = true
                        } else {
                            isShowingAddSheet = true
                        }
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
            .sheet(item: $editingMacro) { macro in
                NavigationStack {
                    MacroEditView(macro: macro)
                }
            }
            .sheet(isPresented: $showingPaywall) {
                SubscriptionPaywallView(reason: paywallReason)
            }
            .sheet(isPresented: $showingFolderSettings) {
                NavigationStack {
                    FolderSettingsView()
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

    // MARK: - Macro Operations

    private func deleteMacros(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(macros[index])
        }
    }

    private func moveMacros(from source: IndexSet, to destination: Int) {
        var sorted = macros
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, macro) in sorted.enumerated() {
            macro.sortOrder = index
        }
    }

    // MARK: - Default Macros (Fixed: single newlines)

    private var defaultMacros: [Macro] {
        return [
            // Markdown Headings
            Macro(trigger: "Heading One", replacement: "# ", isDefault: true, sortOrder: 0),
            Macro(trigger: "Heading Two", replacement: "## ", isDefault: true, sortOrder: 1),
            Macro(trigger: "Heading Three", replacement: "### ", isDefault: true, sortOrder: 2),
            Macro(trigger: "Heading Four", replacement: "#### ", isDefault: true, sortOrder: 3),
            Macro(trigger: "Heading Five", replacement: "##### ", isDefault: true, sortOrder: 4),
            Macro(trigger: "Heading Six", replacement: "###### ", isDefault: true, sortOrder: 5),

            // Markdown Formatting
            Macro(trigger: "Bold", replacement: "**", isDefault: true, sortOrder: 6),
            Macro(trigger: "Italic", replacement: "_", isDefault: true, sortOrder: 7),
            Macro(trigger: "Strikethrough", replacement: "~~", isDefault: true, sortOrder: 8),
            Macro(trigger: "Code Block", replacement: "```", isDefault: true, sortOrder: 9),
            Macro(trigger: "Inline Code", replacement: "`", isDefault: true, sortOrder: 10),
            Macro(trigger: "Quote", replacement: "{newline}> ", isDefault: true, sortOrder: 11),

            // Markdown Lists
            Macro(trigger: "Bullet", replacement: "{newline}- ", isDefault: true, sortOrder: 12),
            Macro(trigger: "Numbered", replacement: "{newline}1. ", isDefault: true, sortOrder: 13),
            Macro(trigger: "Task", replacement: "{newline}- [ ] ", isDefault: true, sortOrder: 14),

            // Clever Macros
            Macro(trigger: "Timestamp", replacement: "{time} - ", isDefault: true, sortOrder: 15),
            Macro(trigger: "New Journal Entry", replacement: "{newline}## {date} at {time}{newline}", isDefault: true, sortOrder: 16),
            Macro(trigger: "Horizontal Rule", replacement: "{newline}---{newline}", isDefault: true, sortOrder: 17),
            Macro(trigger: "Paste", replacement: "{clipboard}", isDefault: true, sortOrder: 18),
            Macro(trigger: "Dropoff", replacement: "{location} - ", isDefault: true, sortOrder: 19),
            Macro(trigger: "Smile", replacement: "😀", isDefault: true, sortOrder: 20),
            Macro(trigger: "Block ID", replacement: "^id-{uuid}", isDefault: true, sortOrder: 21)
        ]
    }

    private func prepopulateIfNeeded() {
        if macros.isEmpty {
            for macro in defaultMacros {
                modelContext.insert(macro)
            }
        }
    }

    private func restoreDefaults() {
        for macro in macros {
            modelContext.delete(macro)
        }
        for macro in defaultMacros {
            modelContext.insert(macro)
        }
    }
}

// MARK: - Add Macro View

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
        .environment(EntitlementManager.shared)
}
