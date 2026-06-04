import SwiftUI

struct InstantCaptureView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = AudioRecorder()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "waveform.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(recorder.isRecording ? .red : .gray)
                .symbolEffect(.pulse, options: .repeating, isActive: recorder.isRecording)
                
            Text(recorder.isRecording ? "Listening..." : "Ready")
                .font(.headline)
                .padding(.top)
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await finishAndSave()
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .handGestureShortcut(.primaryAction)
            }
        }
        .onAppear {
            Task {
                await recorder.startRecording()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                Task {
                    await finishAndSave()
                }
            }
        }
        .onDisappear {
            _ = recorder.stopRecording()
        }
    }
    
    private func finishAndSave() async {
        guard let fileURL = recorder.stopRecording() else {
            dismiss()
            return
        }
        
        let id = UUID()
        var lat: Double? = nil
        var lon: Double? = nil
        
        // Let's blindly fetch location if we record audio, since we don't know the transcript yet
        if let location = await LocationManager.shared.getCurrentLocation() {
            lat = location.coordinate.latitude
            lon = location.coordinate.longitude
        }
        
        WatchConnectivityProvider.shared.sendFile(fileURL, id: id, latitude: lat, longitude: lon)
        
        dismiss()
    }
}

#Preview {
    InstantCaptureView()
}
