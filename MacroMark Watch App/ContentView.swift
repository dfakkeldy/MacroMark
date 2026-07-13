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
    @State private var selectedDate = Calendar.autoupdatingCurrent.startOfDay(for: Date())

    private var today: Date {
        Calendar.autoupdatingCurrent.startOfDay(for: Date())
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 8) {
                Text(today, format: .dateTime.month(.abbreviated).day().year())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Today")

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button(action: {
                            resetToToday()
                            navigationPath.append(.instant)
                        }) {
                            Image(systemName: "mic.fill")
                                .font(.title)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(.blue).interactive(), in: .rect(cornerRadius: 16))
                        .accessibilityLabel("Instant capture")
                        .accessibilityHint("Starts an audio recording immediately.")
                        .accessibilityInputLabels(["Instant capture", "Audio capture", "Record note"])

                        Button(action: {
                            resetToToday()
                            navigationPath.append(.system)
                        }) {
                            Image(systemName: "keyboard.fill")
                                .font(.title)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(.orange).interactive(), in: .rect(cornerRadius: 16))
                        .accessibilityLabel("System capture")
                        .accessibilityHint("Opens the system keyboard and dictation capture.")
                        .accessibilityInputLabels(["System capture", "Keyboard capture", "Dictate note"])
                    }
                    .frame(height: 70)

                    Button(action: {
                        resetToToday()
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
                    DailyLogView()
                }
            }
        }
        .onAppear(perform: resetToToday)
        .onOpenURL { url in
            navigationPath.removeAll()
            resetToToday()
            if url == AppRoute.instantCaptureURL {
                navigationPath.append(.instant)
            } else if url == AppRoute.systemCaptureURL {
                navigationPath.append(.system)
            }
        }
    }

    private func resetToToday() {
        selectedDate = today
    }

    private func navigateToDefaultCapture() {
        resetToToday()

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
