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
            guard let results = result as? [String], let textResult = results.first, !textResult.isEmpty else {
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
