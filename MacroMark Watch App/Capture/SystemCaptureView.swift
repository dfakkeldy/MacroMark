import SwiftUI
import WatchKit
import MacroMarkKit

struct SystemCaptureView: View {
    let targetDate: Date

    @Environment(\.dismiss) private var dismiss
    @State private var capturedText: String?
    @State private var capturedTimestamp: Date?
    @State private var captureTimeZone = TimeZone.current
    @State private var capturedNote: CapturedNote?
    @State private var didPresent = false

    var body: some View {
        VStack {
            if let capturedText {
                ScrollView { Text(capturedText) }
                Text(LocalStore.shared.captureError ?? "Your text is ready to save.")
                    .font(.caption)
                Button("Try saving again") { saveCapturedText() }
            } else {
                ProgressView("Listening...")
            }
        }
        .padding()
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didPresent else { return }
            didPresent = true
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

            let capturedAt = Date()
            let capturedZone = TimeZone.current
            Task { @MainActor in
                capturedText = textResult
                capturedTimestamp = capturedAt
                captureTimeZone = capturedZone
                saveCapturedText()
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

    private func saveCapturedText() {
        guard let capturedText, let capturedTimestamp else { return }
        if capturedNote == nil {
            capturedNote = LocalStore.shared.prepareCapturedNote(capturedText,
                timestamp: capturedTimestamp, timeZone: captureTimeZone, phoneTargetDay: targetDate)
        }
        guard let capturedNote else { return }
        if LocalStore.shared.saveNote(capturedNote) { dismiss() }
    }
}

#Preview {
    SystemCaptureView(targetDate: Date())
}
