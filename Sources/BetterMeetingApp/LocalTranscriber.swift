import AVFoundation
import Foundation
import WhisperKit

enum LocalTranscriptionProgress: Sendable {
    case preparingModel
    case downloadingModel(Double)
    case loadingModel
    case transcribing(Double)
}

actor LocalTranscriber {
    private var whisper: WhisperKit?

    func transcribe(
        audioURL: URL,
        progressHandler: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> [TranscriptSegment] {
        let whisper: WhisperKit
        if let loaded = self.whisper {
            whisper = loaded
        } else {
            progressHandler(.preparingModel)
            let modelFolder = try await WhisperKit.download(
                variant: "small",
                progressCallback: { progress in
                    let fraction = progress.fractionCompleted
                    guard fraction.isFinite else { return }
                    progressHandler(.downloadingModel(min(max(fraction, 0), 1)))
                }
            )

            progressHandler(.loadingModel)
            let loaded = try await WhisperKit(
                modelFolder: modelFolder.path,
                verbose: false,
                prewarm: false,
                load: true,
                download: false
            )
            self.whisper = loaded
            whisper = loaded
        }

        let decodingOptions = DecodingOptions(
            verbose: false,
            wordTimestamps: false,
            chunkingStrategy: .vad
        )
        let audioFile = try AVAudioFile(
            forReading: audioURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate

        whisper.segmentDiscoveryCallback = { segments in
            guard duration > 0, let end = segments.last?.end else { return }
            progressHandler(.transcribing(min(Double(end) / duration, 1)))
        }
        defer { whisper.segmentDiscoveryCallback = nil }

        progressHandler(.transcribing(0))
        let results = try await whisper.transcribe(
            audioPath: audioURL.path,
            audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental),
            decodeOptions: decodingOptions
        )
        progressHandler(.transcribing(1))

        return results.flatMap { result in
            result.segments.compactMap { segment in
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return TranscriptSegment(
                    start: TimeInterval(segment.start),
                    end: TimeInterval(segment.end),
                    text: text,
                    language: result.language
                )
            }
        }
        .sorted { $0.start < $1.start }
    }
}
