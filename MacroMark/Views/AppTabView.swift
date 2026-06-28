import SwiftUI
import SwiftData
import MacroMarkKit

struct AppTabView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            Tab("Inbox", systemImage: "tray.fill") {
                InboxView()
                    .accessibilityIdentifier("inbox.screen")
            }

            Tab("Macros", systemImage: "text.quote") {
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
        .modelContainer(for: [Macro.self, ProcessedNote.self], inMemory: true)
}
