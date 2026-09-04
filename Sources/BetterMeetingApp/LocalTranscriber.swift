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
        progressHandler(.transcribing(0))
        let results = try await transcribeIncrementally(
            audioURL: audioURL,
            using: whisper,
            decodingOptions: decodingOptions,
            progressHandler: progressHandler
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

    private func transcribeIncrementally(
        audioURL: URL,
        using whisper: WhisperKit,
        decodingOptions: DecodingOptions,
        progressHandler: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> [TranscriptionResult] {
        let audioFile = try AVAudioFile(
            forReading: audioURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        let totalSamples = max(1, Int((duration * Double(WhisperKit.sampleRate)).rounded(.up)))
        let maximumChunkLength = whisper.featureExtractor.windowSamples ?? WhisperKit.sampleRate * 30
        let loadingChunkDuration = AudioInputOptions.AudioLoadingMode.defaultChunkDurationSeconds
        let chunker = VADAudioChunker(vad: whisper.voiceActivityDetector)

        var currentTime = 0.0
        var bufferStartSample = 0
        var audioBuffer: [Float] = []
        var allResults: [TranscriptionResult] = []

        while true {
            try Task.checkCancellation()

            while audioBuffer.count <= maximumChunkLength && currentTime < duration {
                let chunkEnd = min(currentTime + loadingChunkDuration, duration)
                let samples = try AudioProcessor.loadAudioAsFloatArray(
                    fromPath: audioURL.path,
                    startTime: currentTime,
                    endTime: chunkEnd
                )
                audioBuffer.append(contentsOf: samples)
                currentTime = chunkEnd
            }

            if audioBuffer.isEmpty { break }
            let reachedEnd = currentTime >= duration
            let chunks = try await chunker.chunkAll(
                audioArray: audioBuffer,
                maxChunkLength: maximumChunkLength,
                decodeOptions: nil
            )
            let readyChunks = reachedEnd
                ? chunks
                : chunks.prefix {
                    $0.seekOffsetIndex + maximumChunkLength <= audioBuffer.count
                }

            var consumedSamples = 0
            for chunk in readyChunks {
                try Task.checkCancellation()
                let globalOffset = bufferStartSample + chunk.seekOffsetIndex
                let chunkResults = try await whisper.transcribe(
                    audioArray: chunk.audioSamples,
                    audioArrayOffset: globalOffset,
                    decodeOptions: decodingOptions
                )
                let seekTime = Float(globalOffset) / Float(WhisperKit.sampleRate)
                for result in chunkResults {
                    result.segments = result.segments.map {
                        TranscriptionUtilities.updateSegmentTimings(
                            segment: $0,
                            seekOffsetIndex: globalOffset
                        )
                    }
                    result.seekTime = seekTime + (result.seekTime ?? 0)
                }
                allResults.append(contentsOf: chunkResults)

                consumedSamples = chunk.seekOffsetIndex + chunk.audioSamples.count
                let processedSamples = bufferStartSample + consumedSamples
                let fraction = min(Double(processedSamples) / Double(totalSamples), 1)
                progressHandler(.transcribing(fraction))
            }

            if reachedEnd { break }
            guard consumedSamples > 0 else {
                throw LocalTranscriptionError.cannotAdvance
            }
            bufferStartSample += consumedSamples
            audioBuffer = Array(audioBuffer[consumedSamples...])
        }

        progressHandler(.transcribing(1))
        return allResults.sorted { ($0.seekTime ?? 0) < ($1.seekTime ?? 0) }
    }
}

enum LocalTranscriptionError: LocalizedError {
    case cannotAdvance

    var errorDescription: String? {
        "The recording could not be divided into transcription segments."
    }
}
