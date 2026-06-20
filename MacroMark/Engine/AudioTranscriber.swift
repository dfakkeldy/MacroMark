import Foundation
@preconcurrency import Speech
import AVFoundation

final class AudioTranscriber {
    /// Speech framework has a ~60s request limit; 50s leaves headroom.
    private static let chunkDurationSeconds: TimeInterval = 50
    private static let timescale: CMTimeScale = 1000

    /// The outcome of a transcription session. When some chunks fail but others
    /// succeed, the partial text is returned with `hadPartialFailure = true` so
    /// the UI can surface a warning. Only when every chunk fails does this throw
    /// (the caller defers reprocessing via the write-ahead log).
    struct TranscriptionResult {
        let text: String
        let hadPartialFailure: Bool
    }

    static func transcribe(fileURL: URL) async throws -> TranscriptionResult {
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

        let chunkURLs = try await splitAudio(url: fileURL, maxDuration: Self.chunkDurationSeconds)
        var fullTranscript = ""
        var chunkErrors: [Error] = []

        for url in chunkURLs {
            let request = SFSpeechURLRecognitionRequest(url: url)

            do {
                nonisolated(unsafe) var speechTask: SFSpeechRecognitionTask?
                let chunkText: String = try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        var isResumed = false
                        speechTask = recognizer.recognitionTask(with: request) { result, error in
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
                } onCancel: {
                    speechTask?.cancel()
                }

                if !fullTranscript.isEmpty && !chunkText.isEmpty {
                    fullTranscript += " "
                }
                fullTranscript += chunkText
            } catch {
                chunkErrors.append(error)
                #if DEBUG
                print("Failed to transcribe chunk: \(error)")
                #endif
            }

            if url != fileURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // If all chunks failed and we have errors, throw a composite error with partial transcript.
        if fullTranscript.isEmpty && !chunkErrors.isEmpty {
            throw NSError(
                domain: "AudioTranscriber",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "All transcription chunks failed.",
                    "chunkErrors": chunkErrors
                ]
            )
        }

        return TranscriptionResult(
            text: fullTranscript,
            hadPartialFailure: !chunkErrors.isEmpty
        )
    }

    private static func splitAudio(url: URL, maxDuration: TimeInterval) async throws -> [URL] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        if duration <= maxDuration { return [url] }

        var urls = [URL]()
        var startTime = 0.0
        while startTime < duration {
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw NSError(domain: "AudioTranscriber", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
            }
            let chunkURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")

            let endTime = min(startTime + maxDuration, duration)
            let timeRange = CMTimeRange(start: CMTime(seconds: startTime, preferredTimescale: Self.timescale), end: CMTime(seconds: endTime, preferredTimescale: Self.timescale))
            exportSession.timeRange = timeRange

            try await exportSession.export(to: chunkURL, as: .m4a)
            urls.append(chunkURL)
            startTime += maxDuration
        }
        return urls
    }
}
