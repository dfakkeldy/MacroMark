import Foundation
import os
@preconcurrency import Speech
import AVFoundation
import MacroMarkKit

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
            let timeout = ContinuationTimeout()
            Task {
                try? await Task.sleep(for: .seconds(5))
                if await timeout.complete() {
                    continuation.resume(returning: SFSpeechRecognizer.authorizationStatus())
                }
            }
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                let authorizationStatus = status
                Task {
                    if await timeout.complete() {
                        continuation.resume(returning: authorizationStatus)
                    }
                }
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
                // The recognition task is created inside the continuation but must
                // be cancellable from the @Sendable `onCancel` handler, which runs in
                // a different isolation domain. An unfair lock gives the assign and
                // cancel mutual exclusion, replacing `nonisolated(unsafe)`, which only
                // silenced the diagnostic without removing the underlying race.
                // (`SFSpeechRecognitionTask` is itself non-Sendable; the lock provides
                // the synchronization, and `@preconcurrency import Speech` accepts the
                // boxed non-Sendable value. `cancel()` is documented thread-safe.)
                let speechTaskBox = OSAllocatedUnfairLock<SFSpeechRecognitionTask?>(initialState: nil)
                let chunkText: String = try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        let resumeGate = ContinuationTimeout()
                        let task = recognizer.recognitionTask(with: request) { @Sendable result, error in
                            let finalTranscript: String?
                            if let result, result.isFinal {
                                finalTranscript = result.bestTranscription.formattedString
                            } else {
                                finalTranscript = nil
                            }

                            guard error != nil || finalTranscript != nil else { return }

                            Task {
                                guard await resumeGate.complete() else { return }
                                if let error {
                                    continuation.resume(throwing: error)
                                } else if let finalTranscript {
                                    continuation.resume(returning: finalTranscript)
                                }
                            }
                        }
                        speechTaskBox.withLock { $0 = task }
                    }
                } onCancel: {
                    speechTaskBox.withLock { $0?.cancel() }
                }

                if !fullTranscript.isEmpty && !chunkText.isEmpty {
                    fullTranscript += "\n"
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
