import Foundation
@preconcurrency import AVFoundation
import Observation
import WatchKit
import MacroMarkKit

@MainActor
@Observable
final class AudioRecorder {
    /// AAC sample rate for watch voice notes — speech-band, keeps files small.
    private static let sampleRate = 12_000

    var isRecording = false
    var recordingURL: URL?

    private var audioRecorder: AVAudioRecorder?

    func startRecording() async {
        let session = AVAudioSession.sharedInstance()
        do {
            let hasPermission = await AVAudioApplication.requestRecordPermission()
            guard hasPermission else {
                #if DEBUG
                print("No permission to record")
                #endif
                return
            }

            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

            let documentPath = FileManager.default.temporaryDirectory
            let url = documentPath.appendingPathComponent("\(UUID().uuidString).\(StorageFormat.audioFileExtension)")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: Self.sampleRate,
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
            #if DEBUG
            print("Failed to start recording: \(error)")
            #endif
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
