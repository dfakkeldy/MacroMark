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
            // `result` is `[Any]?`; take the first element directly. A non-String
            // pick (e.g. an emoji) must not be silently dropped by an `as? [String]`
            // cast that would yield nil.
            guard let first = result?.first else {
                dismiss()
                return
            }
            let textResult = (first as? String) ?? String(describing: first)
            guard !textResult.isEmpty else {
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
