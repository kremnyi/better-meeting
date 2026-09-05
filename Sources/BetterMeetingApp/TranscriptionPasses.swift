import Foundation
import WhisperKit

struct ScoredSegment: Codable, Equatable, Sendable {
    let start: Double
    let end: Double
    let text: String
    let lang: String
    let score: Float
    let nospeech: Float

    var transcript: TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text, language: lang)
    }
}

enum TranscriptionLanguage: String, CaseIterable {
    case auto, uk, ru, en

    var languages: [String] { self == .auto ? ["uk", "ru", "en"] : [rawValue] }
    var label: String {
        switch self {
        case .auto: "Auto (UK, RU, EN)"
        case .uk: "Ukrainian"
        case .ru: "Russian"
        case .en: "English"
        }
    }
}

enum TranscriptionPasses {
    private static let backend = "WhisperKit-1.1.0-nospeech-2"

    private struct Cache: Codable {
        let model: String
        let backend: String
        let options: Data
        var hints: String? = nil
        let audioSize: Int?
        let audioModified: Date?
        let segments: [ScoredSegment]
    }

    static func options(language: String) -> DecodingOptions {
        DecodingOptions(
            language: language, detectLanguage: false, skipSpecialTokens: true,
            wordTimestamps: false, concurrentWorkerCount: 1, chunkingStrategy: .vad
        )
    }

    static func run(
        audioURL: URL, languages: [String], hints: String = "",
        progressHandler: @Sendable (LocalTranscriptionProgress) -> Void,
        transcribe: (DecodingOptions, Int) async throws -> [ScoredSegment]
    ) async throws -> [TranscriptSegment] {
        // URL resource values can be stale when an existing audio file is replaced.
        let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
        let hints = hints.trimmingCharacters(in: .whitespacesAndNewlines)
        let audioSize = (attributes[.size] as? NSNumber)?.intValue
        let audioModified = attributes[.modificationDate] as? Date
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var segments: [ScoredSegment] = []
        for (index, language) in languages.enumerated() {
            try Task.checkCancellation()
            let options = options(language: language)
            let encodedOptions = try encoder.encode(options)
            let cacheURL = audioURL.deletingLastPathComponent().appendingPathComponent("pass_\(language).json")
            let cache = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
            let pass: [ScoredSegment]
            if let cache, cache.model == LocalTranscriber.modelVariant,
               cache.backend == backend, cache.options == encodedOptions,
               (cache.hints ?? "") == hints,
               cache.audioSize == audioSize, cache.audioModified == audioModified {
                pass = cache.segments
            } else {
                pass = try await transcribe(options, index)
                try Task.checkCancellation()
                let cache = Cache(
                    model: LocalTranscriber.modelVariant, backend: backend,
                    options: encodedOptions, hints: hints.isEmpty ? nil : hints, audioSize: audioSize,
                    audioModified: audioModified, segments: pass
                )
                try encoder.encode(cache).write(to: cacheURL, options: .atomic)
            }
            segments.append(contentsOf: pass)
            progressHandler(.transcribing(
                Double(index + 1) / Double(languages.count),
                language: language, pass: index + 1, total: languages.count
            ))
        }
        return (languages.count > 1 ? merge(segments) : segments.sorted { $0.start < $1.start }).map(\.transcript)
    }

    // Port of GivenFLY/better-meeting's asr.py _merge at e9b524d.
    // ponytail: upstream's quadratic scan; sweep the intervals if long meetings make merging slow.
    static func merge(_ passes: [ScoredSegment]) -> [ScoredSegment] {
        let segments = passes.filter { !($0.nospeech > 0.6 && $0.score < -1) }
            .sorted { $0.start < $1.start }
        guard var cursor = segments.first?.start else { return [] }
        var merged: [ScoredSegment] = []
        while true {
            let candidates = segments.filter { $0.end > cursor + 0.2 && $0.start <= cursor + 2 }
            // Keep the first candidate on ties, matching Python's max().
            if let best = candidates.reduce(nil as ScoredSegment?, { best, next in
                guard let best else { return next }
                return next.score > best.score ? next : best
            }) {
                merged.append(best)
                cursor = best.end
            } else if let next = segments.first(where: { $0.start > cursor }) {
                cursor = next.start
            } else {
                break
            }
        }
        return merged
    }
}
