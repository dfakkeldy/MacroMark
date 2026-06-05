import Foundation
@preconcurrency import AVFoundation
import Observation
import WatchKit

@MainActor
@Observable
final class AudioRecorder {
    var isRecording = false
    var recordingURL: URL?

    private var audioRecorder: AVAudioRecorder?

    func startRecording() async {
        let session = AVAudioSession.sharedInstance()
        do {
            let hasPermission = await AVAudioApplication.requestRecordPermission()
            guard hasPermission else {
                print("No permission to record")
                return
            }

            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

            let documentPath = FileManager.default.temporaryDirectory
            let url = documentPath.appendingPathComponent("\(UUID().uuidString).m4a")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.prepareToRecord()

            // Start recording immediately
            audioRecorder?.record()

            // Wait for the microphone hardware to fully spin up and buffer
            try? await Task.sleep(for: .seconds(1))

            // Signal the user exactly when it's safe to start talking
            WKInterfaceDevice.current().play(.start)

            self.recordingURL = url
            self.isRecording = true

        } catch {
            print("Failed to start recording: \(error)")
            self.isRecording = false
        }
    }

    func stopRecording() -> URL? {
        audioRecorder?.stop()
        isRecording = false

        // Deactivate the audio session so other audio (alarms, calls, other apps)
        // can play or record after recording ends.
        try? AVAudioSession.sharedInstance().setActive(false)

        return recordingURL
    }
}
