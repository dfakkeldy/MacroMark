import SwiftUI

enum CaptureMode: Hashable {
    case instant
    case system
    case dailyLog
}

struct ContentView: View {
    @AppStorage("captureMode") private var captureMode: String = "audio"
    @State private var navigationPath = [CaptureMode]()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 20) {
                Button("Instant Capture") {
                    navigationPath.append(.instant)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .handGestureShortcut(captureMode == "audio" ? .primaryAction : nil)
                
                Button("System Capture") {
                    navigationPath.append(.system)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .handGestureShortcut(captureMode == "system" ? .primaryAction : nil)
                
                Button("Today's Log") {
                    navigationPath.append(.dailyLog)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
            .navigationTitle("MacroMark")
            .navigationDestination(for: CaptureMode.self) { mode in
                switch mode {
                case .instant:
                    InstantCaptureView()
                case .system:
                    SystemCaptureView()
                case .dailyLog:
                    DailyLogView()
                }
            }
        }
        .onOpenURL { url in
            if url.scheme == "macromark" && url.host == "capture" {
                let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                navigationPath.removeAll()
                if path == "instant" {
                    navigationPath.append(.instant)
                } else if path == "system" {
                    navigationPath.append(.system)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
