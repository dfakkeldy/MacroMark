import SwiftUI
import MacroMarkKit

enum CaptureMode: Hashable {
    case instant
    case system
    case dailyLog
    case replies
    case deliveries
}

struct ContentView: View {
    @AppStorage(UserDefaultsKey.captureMode.rawValue) private var captureMode: String = "audio"
    @State private var navigationPath = [CaptureMode]()
    @State private var selectedDate = Calendar.autoupdatingCurrent.startOfDay(for: Date())
    @AppStorage("directSend.selectedMode") private var deliveryMode = "phone"

    private var today: Date {
        Calendar.autoupdatingCurrent.startOfDay(for: Date())
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
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
                Text(deliveryMode == "direct" ? "Text: Direct Send · Audio: Phone" : "Delivery: Phone")
                    .font(.caption2).foregroundStyle(.secondary)
                NavigationLink(value: CaptureMode.deliveries) {
                    Label("\(LocalStore.shared.pendingCount) pending", systemImage: "arrow.up.circle")
                }
                NavigationLink(value: CaptureMode.replies) {
                    Label("Replies", systemImage: "text.bubble")
                }
                if LocalStore.shared.captureError != nil {
                    Text("Note queue needs attention").font(.caption2).foregroundStyle(.orange)
                }
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
                case .replies:
                    DirectReplyView()
                case .deliveries:
                    DeliveryStatusView()
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
            } else if url == AppRoute.directSendRepliesURL {
                navigationPath.append(.replies)
            } else if url == AppRoute.deliveryStatusURL {
                navigationPath.append(.deliveries)
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
