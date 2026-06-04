import SwiftUI
import WatchKit

struct SystemCaptureView: View {
    @State private var text: String = ""
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

            text = textResult
            dismiss()

            Task.detached {
                ProcessInfo.processInfo.performExpiringActivity(withReason: "Save Dictation") { expired in
                    if !expired {
                        let semaphore = DispatchSemaphore(value: 0)
                        Task {
                            await SystemCaptureView.finishAndSave(text: textResult)
                            semaphore.signal()
                        }
                        semaphore.wait()
                    }
                }
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
