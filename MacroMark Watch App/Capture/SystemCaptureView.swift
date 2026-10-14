import SwiftUI
import WatchKit
import MacroMarkKit

struct SystemCaptureView: View {
    let targetDate: Date

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            ProgressView("Listening...")
        }
        .padding()
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                presentDictation()
            }
        }
    }

    private func presentDictation() {
        WKExtension.shared().visibleInterfaceController?.presentTextInputController(withSuggestions: nil, allowedInputMode: .plain) { result in
            guard let textResult = Self.extractedText(from: result) else {
                dismiss()
                return
            }

            dismiss()

            // Enqueue into the durable LocalStore queue directly. The work is
            // trivial (a UserDefaults write on the MainActor); wrapping it in
            // `performExpiringActivity` + `DispatchSemaphore.wait()` risks
            // deadlocking the cooperative pool on watchOS.
            Task {
                let timestamp = DaySelection.timestamp(onSelectedDay: targetDate)
                await SystemCaptureView.finishAndSave(text: textResult, timestamp: timestamp)
            }
        }
    }

    static func extractedText(from result: Any?) -> String? {
        let rawValue: Any?
        if let strings = result as? [String] {
            rawValue = strings.first
        } else if let values = result as? [Any] {
            rawValue = values.first
        } else {
            rawValue = result
        }

        guard let rawValue else { return nil }
        let text = (rawValue as? String) ?? String(describing: rawValue)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func finishAndSave(text: String, timestamp: Date) async {
        if !text.isEmpty {
            await MainActor.run {
                LocalStore.shared.addNote(text, timestamp: timestamp)
            }
        }
    }
}

#Preview {
    SystemCaptureView(targetDate: Date())
}
