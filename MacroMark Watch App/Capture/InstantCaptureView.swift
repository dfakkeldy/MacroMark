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
                    finishAndSave()
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
                finishAndSave()
            }
        }
        .onDisappear {
            _ = recorder.stopRecording()
        }
    }
    
    private func finishAndSave() {
        guard let fileURL = recorder.stopRecording() else {
            dismiss()
            return
        }
        dismiss()

        // Enqueue the recording into the durable LocalStore queue. The work is
        // trivial (a file move + a UserDefaults write on the MainActor), so it
        // needs neither `performExpiringActivity` nor a semaphore — blocking a
        // cooperative-pool thread on `DispatchSemaphore.wait()` waiting for a
        // MainActor hop can deadlock under pool pressure on watchOS, losing the
        // recording before it ever reaches the WAL.
        Task {
            await InstantCaptureView.processAudioFile(fileURL: fileURL, timestamp: Date())
        }
    }

    private static func processAudioFile(fileURL: URL, timestamp: Date) async {
        let id = UUID()

        await MainActor.run {
            // Persist to a durable queue + retry until the phone ACKs it.
            // Never fire-and-forget: a dropped transfer must not lose the recording.
            LocalStore.shared.enqueueAudio(from: fileURL, id: id, timestamp: timestamp)
        }
    }
}

#Preview {
    InstantCaptureView()
}
