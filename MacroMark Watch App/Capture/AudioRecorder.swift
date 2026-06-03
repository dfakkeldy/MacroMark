import Foundation
import AVFoundation
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
            let hasPermission = await session.hasPermissionToRecord()
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
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.prepareToRecord()
            
            // Allow the Watch microphone hardware to spin up completely
            try? await Task.sleep(for: .milliseconds(300))
            
            audioRecorder?.record()
            
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
        return recordingURL
    }
}

extension AVAudioSession {
    func hasPermissionToRecord() async -> Bool {
        await withCheckedContinuation { continuation in
            requestRecordPermission { authorized in
                continuation.resume(returning: authorized)
            }
        }
    }
}
