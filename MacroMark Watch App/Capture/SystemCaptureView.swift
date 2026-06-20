import SwiftUI
import WatchKit

struct SystemCaptureView: View {
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
                await SystemCaptureView.finishAndSave(text: textResult)
            }
        }
    }

    private static func finishAndSave(text: String) async {
        if !text.isEmpty {
            await MainActor.run {
                LocalStore.shared.addNote(text)
            }
        }
    }
}

#Preview {
    SystemCaptureView()
}
