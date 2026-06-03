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
                    navigateToDefaultCapture()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .handGestureShortcut(.primaryAction)

                Button("System Capture") {
                    navigationPath.append(.system)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

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

    private func navigateToDefaultCapture() {
        switch captureMode {
        case "audio":
            navigationPath.append(.instant)
        case "system":
            navigationPath.append(.system)
        default:
            navigationPath.append(.instant)
        }
    }
}

#Preview {
    ContentView()
}
