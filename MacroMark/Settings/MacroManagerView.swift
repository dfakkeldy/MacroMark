import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Speech
import MacroMarkKit

struct MacroManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Macro.sortOrder, order: .forward) private var macros: [Macro]

    @AppStorage(UserDefaultsKey.captureMode.rawValue) private var captureMode: String = "audio"
    @AppStorage(UserDefaultsKey.customSaveBookmark.rawValue) private var customSaveBookmark: Data?
    @AppStorage(UserDefaultsKey.defaultExportTarget.rawValue) private var defaultExportTarget: ExportTarget = .iCloud
    @AppStorage(UserDefaultsKey.autoExportEnabled.rawValue) private var autoExportEnabled: Bool = false
    @State private var isShowingAddSheet = false
    @State private var showingFolderPicker = false
    @State private var editingMacro: Macro?
    @State private var showingPaywall = false
    @State private var showingFolderSettings = false
    @State private var showingRestoreConfirmation = false
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
                Section("iCloud Storage Location") {
                    Button(customSaveBookmark == nil ? "Choose Save Location..." : "Change Save Location...") {
                        showingFolderPicker = true
                    }
                    if customSaveBookmark != nil {
                        Button("Reset to Default (iCloud)", role: .destructive) {
                            customSaveBookmark = nil
                        }
                    }
                }
                
                // MARK: Export & Integrations
                Section("Export Options") {
                    Picker("Default Destination", selection: $defaultExportTarget) {
                        ForEach(ExportTarget.allCases) { target in
                            Label(target.rawValue, systemImage: target.iconName).tag(target)
                        }
                    }
                    
                    if defaultExportTarget != .iCloud && defaultExportTarget != .shareSheet {
                        Toggle("Auto-Export on Completion", isOn: $autoExportEnabled)
                        if autoExportEnabled {
                            Text("When notes finish processing on the phone, MacroMark will attempt to open \(defaultExportTarget.rawValue) automatically. Note: this requires your phone to be unlocked.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                        Text("\(customMacroCount)" + (entitlements.isEntitled ? "" : "/\(EntitlementManager.maxFreeMacros) free"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Restore Default Macros", role: .destructive) {
                        showingRestoreConfirmation = true
                    }
                }
            }
            .navigationTitle("MacroMark")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") {
                        if !entitlements.isEntitled && customMacroCount >= EntitlementManager.maxFreeMacros {
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
                    #if DEBUG
                    print("Error selecting folder: \(error)")
                    #endif
                }
            }
            .confirmationDialog("Restore defaults?", isPresented: $showingRestoreConfirmation) {
                Button("Restore Defaults", role: .destructive) { restoreDefaults() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Your custom macros will be kept. Only the built-in defaults will be reset.")
            }
            .onAppear {
                prepopulateIfNeeded()
            }
        }
    }

    // MARK: - Macro Operations

    private func deleteMacros(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(macros[index])
        }
        MacroProcessor.invalidateRegexCache()
    }

    private func moveMacros(from source: IndexSet, to destination: Int) {
        var sorted = macros
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, macro) in sorted.enumerated() {
            macro.sortOrder = index
        }
        // sortOrder changes don't affect trigger patterns, but invalidation is
        // cheap and keeps the cache in lockstep with the macro set.
        MacroProcessor.invalidateRegexCache()
    }

    // MARK: - Default Macros (Fixed: single newlines)

    private var defaultMacros: [Macro] {
        return [
            // Markdown Headings
            Macro(trigger: "Heading One", replacement: "# ", isDefault: true, sortOrder: 0),
            Macro(trigger: "Heading Two", replacement: "## ", isDefault: true, sortOrder: 1),
            Macro(trigger: "Heading To", replacement: "## ", notes: "Dictation often mishears 'Heading Two' as 'Heading To'.", isDefault: true, sortOrder: 1),
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
            Macro(trigger: "Quote", replacement: "> ", isDefault: true, sortOrder: 11),

            // Markdown Lists
            Macro(trigger: "Bullet", replacement: "- ", isDefault: true, sortOrder: 12),
            Macro(trigger: "Numbered", replacement: "1. ", isDefault: true, sortOrder: 13),
            Macro(trigger: "Task", replacement: "- [ ] ", isDefault: true, sortOrder: 14),

            // Clever Macros
            Macro(trigger: "Timestamp", replacement: "{time} - ", notes: "Inserts the current time.", isDefault: true, sortOrder: 15),
            Macro(trigger: "New Journal Entry", replacement: "## {date} at {time}", notes: "Creates a new daily journal entry heading.", isDefault: true, sortOrder: 16),
            Macro(trigger: "Horizontal Rule", replacement: "---", isDefault: true, sortOrder: 17),
            Macro(trigger: "Paste", replacement: "{clipboard}", notes: "Pastes whatever is currently on your clipboard.", isDefault: true, sortOrder: 18),
            Macro(trigger: "Dropoff", replacement: "{location} - ", notes: "Inserts your current street address.", isDefault: true, sortOrder: 19),
            Macro(trigger: "Smile", replacement: "😀", isDefault: true, sortOrder: 20),
            Macro(trigger: "Block ID", replacement: "^id-{uuid}", notes: "Generates a unique identifier for block references.", isDefault: true, sortOrder: 21),
            Macro(trigger: "Not", replacement: "{backspace}", notes: "Deletes the character before it. Say 'new line' then 'not' to end a hashtag without leaving a newline. ⚠️ 'Not' is a common word — rename this trigger if it fires accidentally.", isDefault: true, sortOrder: 22)
        ]
    }

    private func prepopulateIfNeeded() {
        if macros.isEmpty {
            for macro in defaultMacros {
                modelContext.insert(macro)
            }
            try? modelContext.save()
        }
    }

    private func restoreDefaults() {
        // Only reset the built-in defaults; user-created custom macros survive.
        for macro in macros where macro.isDefault {
            modelContext.delete(macro)
        }
        for macro in defaultMacros {
            modelContext.insert(macro)
        }
        try? modelContext.save()
        MacroProcessor.invalidateRegexCache()
    }
}

#Preview {
    MacroManagerView()
        .modelContainer(for: Macro.self, inMemory: true)
        .environment(EntitlementManager.shared)
}
