import SwiftUI
import MacroMarkKit

enum CaptureMode: Hashable {
    case instant
    case system
    case dailyLog
}

struct ContentView: View {
    @AppStorage(UserDefaultsKey.captureMode.rawValue) private var captureMode: String = "audio"
    @State private var navigationPath = [CaptureMode]()
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 8) {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: {
                            navigationPath.append(.instant)
                        }) {
                            Label("Instant Capture", systemImage: "mic.fill")
                                .labelStyle(.iconOnly)
                                .font(.title)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: 16))

                        Button(action: {
                            navigationPath.append(.system)
                        }) {
                            Label("Dictation", systemImage: "keyboard.fill")
                                .labelStyle(.iconOnly)
                                .font(.title)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(.orange).interactive(), in: .rect(cornerRadius: 16))
                    }
                    .frame(height: 70)

                    Button(action: {
                        navigationPath.append(.dailyLog)
                    }) {
                        Text("Daily Log")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.purple).interactive(), in: .rect(cornerRadius: 16))
                }
            }
            .navigationTitle("MacroMark")
            .background {
                // Hidden button to catch the watchOS Double Tap (Pinch) gesture
                Button(action: {
                    navigateToDefaultCapture()
                }) {
                    EmptyView()
                }
                .buttonStyle(.plain)
                .handGestureShortcut(.primaryAction)
            }
            .navigationDestination(for: CaptureMode.self) { mode in
                switch mode {
                case .instant:
                    InstantCaptureView(targetDate: selectedDate)
                case .system:
                    SystemCaptureView(targetDate: selectedDate)
                case .dailyLog:
                    DailyLogView(selectedDate: $selectedDate)
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
