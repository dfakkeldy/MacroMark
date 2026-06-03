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
        .navigationTitle("System")
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
            Task {
                await finishAndSave()
            }
        }
    }
    
    private func finishAndSave() async {
        if !text.isEmpty {
            var lat: Double? = nil
            var lon: Double? = nil
            
            if text.contains("{location}") {
                if let location = await LocationManager.shared.getCurrentLocation() {
                    lat = location.coordinate.latitude
                    lon = location.coordinate.longitude
                }
            }
            
            LocalStore.shared.addNote(text, latitude: lat, longitude: lon)
        }
        dismiss()
    }
}

#Preview {
    SystemCaptureView()
}
