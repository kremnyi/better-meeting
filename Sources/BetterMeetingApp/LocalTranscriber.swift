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
    private let downloadBase: URL

    static let defaultDownloadBase = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("huggingface")

    init(downloadBase: URL = defaultDownloadBase) {
        self.downloadBase = downloadBase
    }

    static func cachedModelFolder(in downloadBase: URL = defaultDownloadBase) -> URL? {
        let folder = downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-small")
        return hasModelFiles(in: folder) ? folder : nil
    }

    static func hasModelFiles(in folder: URL) -> Bool {
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { name in
            ["mlmodelc", "mlpackage"].contains { ext in
                let manifest = folder.appendingPathComponent("\(name).\(ext)")
                    .appendingPathComponent(ext == "mlmodelc" ? "coremldata.bin" : "Manifest.json")
                let values = try? manifest.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                return values?.isRegularFile == true && (values?.fileSize ?? 0) > 0
            }
        }
    }

    @discardableResult
    func prepare(
        progressHandler: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> WhisperKit {
        if let whisper { return whisper }
        progressHandler(.preparingModel)
        let modelFolder: URL
        if let cached = Self.cachedModelFolder(in: downloadBase) {
            modelFolder = cached
        } else {
            modelFolder = try await WhisperKit.download(
                variant: "openai_whisper-small",
                downloadBase: downloadBase,
                progressCallback: { progress in
                    let fraction = progress.fractionCompleted
                    guard fraction.isFinite else { return }
                    progressHandler(.downloadingModel(min(max(fraction, 0), 1)))
                }
            )
        }

        progressHandler(.loadingModel)
        let loaded = try await WhisperKit(
            modelFolder: modelFolder.path,
            tokenizerFolder: downloadBase,
            verbose: false,
            prewarm: false,
            load: true,
            download: false
        )
        whisper = loaded
        return loaded
    }

    func transcribe(
        audioURL: URL,
        progressHandler: @escaping @Sendable (LocalTranscriptionProgress) -> Void
    ) async throws -> [TranscriptSegment] {
        let whisper = try await prepare(progressHandler: progressHandler)

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
