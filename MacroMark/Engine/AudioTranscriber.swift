import Foundation
import Speech

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
        
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = true
        
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}
