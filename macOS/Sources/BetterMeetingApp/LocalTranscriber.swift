import Foundation
import WhisperKit

actor LocalTranscriber {
    private var whisper: WhisperKit?

    func transcribe(audioURL: URL) async throws -> [TranscriptSegment] {
        let whisper: WhisperKit
        if let loaded = self.whisper {
            whisper = loaded
        } else {
            let loaded = try await WhisperKit(
                model: "small",
                verbose: false,
                prewarm: false,
                load: true,
                download: true
            )
            self.whisper = loaded
            whisper = loaded
        }

        let inputOptions = AudioInputOptions(audioLoadingMode: .incremental)
        let decodingOptions = DecodingOptions(
            verbose: false,
            wordTimestamps: false,
            chunkingStrategy: .vad
        )
        let results = try await whisper.transcribe(
            audioPath: audioURL.path,
            audioInputOptions: inputOptions,
            decodeOptions: decodingOptions
        )

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
