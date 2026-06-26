import SwiftUI
import MacroMarkKit

private enum Layout {
    static let captureRowHeight: CGFloat = 70
    static let dailyLogMinHeight: CGFloat = 44
}

/// Where the watch navigates to. Distinct from `MacroMarkKit.CaptureMode`
/// (audio/system), which is the user's stored default capture mode.
enum CaptureDestination: Hashable {
    case instant
    case system
    case dailyLog
}

struct ContentView: View {
    @AppStorage(UserDefaultsKey.captureMode.rawValue) private var captureMode: String = CaptureMode.audio.rawValue
    @State private var navigationPath = [CaptureDestination]()
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
                            Image(systemName: "mic.fill")
                                .font(.title)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: 16))

                        Button(action: {
                            navigationPath.append(.system)
                        }) {
                            Image(systemName: "keyboard.fill")
                                .font(.title)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(.orange).interactive(), in: .rect(cornerRadius: 16))
                    }
                    .frame(height: Layout.captureRowHeight)

                    Button(action: {
                        navigationPath.append(.dailyLog)
                    }) {
                        Text("Daily Log")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: Layout.dailyLogMinHeight)
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
            .navigationDestination(for: CaptureDestination.self) { mode in
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
        switch CaptureMode(rawValue: captureMode) {
        case .system:
            navigationPath.append(.system)
        default: // .audio or unrecognized
            navigationPath.append(.instant)
        }
    }
}

#Preview {
    ContentView()
}
