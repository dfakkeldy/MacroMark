import SwiftUI
import SwiftData
import MacroMarkKit

struct AppTabView: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        @Bindable var navigation = navigation

        TabView(selection: $navigation.selectedTab) {
            Tab("Inbox", systemImage: "tray.fill", value: .inbox) {
                InboxView()
                    .accessibilityIdentifier("inbox.screen")
            }

            Tab("Macros", systemImage: "text.quote", value: .macros) {
                MacroManagerView()
                    .accessibilityIdentifier("macros.screen")
            }
        }
        .task {
            ScreenshotMode.seedIfNeeded(in: modelContext)
        }
    }
}

#Preview {
    AppTabView()
        .environment(AppNavigation())
        .modelContainer(for: [Macro.self, ProcessedNote.self], inMemory: true)
}
