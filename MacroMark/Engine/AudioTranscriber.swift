import Foundation
import Speech
import AVFoundation

final class AudioTranscriber {
    static func transcribe(fileURL: URL) async throws -> String {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard status == .authorized else {
            throw NSError(domain: "AudioTranscriber", code: 1, userInfo: [NSLocalizedDescriptionKey: "No speech recognition permission"])
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw NSError(domain: "AudioTranscriber", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
        }
        
        let chunkURLs = try await splitAudio(url: fileURL, maxDuration: 50.0)
        var fullTranscript = ""
        
        for url in chunkURLs {
            let request = SFSpeechURLRecognitionRequest(url: url)
            
            do {
                let chunkText: String = try await withCheckedThrowingContinuation { continuation in
                    var isResumed = false
                    recognizer.recognitionTask(with: request) { result, error in
                        if isResumed { return }
                        if let error = error {
                            isResumed = true
                            continuation.resume(throwing: error)
                            return
                        }
                        
                        if let result = result, result.isFinal {
                            isResumed = true
                            continuation.resume(returning: result.bestTranscription.formattedString)
                        }
                    }
                }
                
                if !fullTranscript.isEmpty && !chunkText.isEmpty {
                    fullTranscript += " "
                }
                fullTranscript += chunkText
            } catch {
                print("Failed to transcribe chunk: \(error)")
            }
            
            if url != fileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        
        return fullTranscript
    }
    
    private static func splitAudio(url: URL, maxDuration: TimeInterval) async throws -> [URL] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        if duration <= maxDuration { return [url] }
        
        var urls = [URL]()
        var startTime = 0.0
        while startTime < duration {
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw NSError(domain: "AudioTranscriber", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
            }
            let chunkURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")

            let endTime = min(startTime + maxDuration, duration)
            let timeRange = CMTimeRange(start: CMTime(seconds: startTime, preferredTimescale: 1000), end: CMTime(seconds: endTime, preferredTimescale: 1000))
            exportSession.timeRange = timeRange

            try await exportSession.export(to: chunkURL, as: .m4a)
            urls.append(chunkURL)
            startTime += maxDuration
        }
        return urls
    }
}
