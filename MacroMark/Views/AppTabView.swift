import SwiftUI
import SwiftData
import MacroMarkKit

struct AppTabView: View {
    var body: some View {
        TabView {
            InboxView()
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }
            
            MacroManagerView()
                .tabItem {
                    Label("Macros", systemImage: "text.quote")
                }
        }
    }
}

#Preview {
    AppTabView()
        .modelContainer(for: [Macro.self, ProcessedNote.self], inMemory: true)
}
