import AVFoundation
import CoreML
import WhisperKit
import XCTest
@testable import BetterMeetingApp

final class TranscriptionPassTests: XCTestCase {
    private enum Interrupted: Error { case pass }

    func testOriginalConfidenceMergeAndSilenceRules() {
        let segments = [
            segment(0, 2, "uk", -0.1), segment(0, 2, "ru", -0.4),
            segment(2, 4, "en", -0.2), segment(2, 4, "uk", -0.7),
            segment(4, 6, "ru", -0.3), segment(6, 8, "en", -1.5, silence: 0.9),
            segment(10, 12, "uk", -0.4), segment(14, 16, "en", -0.5, silence: 0.9)
        ]
        let merged = TranscriptionPasses.merge(segments)
        XCTAssertEqual(merged.map(\.lang), ["uk", "en", "ru", "uk", "en"])
        XCTAssertEqual(merged.map(\.start), [0, 2, 4, 10, 14])
        XCTAssertTrue(TranscriptionPasses.merge([]).isEmpty)
        XCTAssertEqual(TranscriptionPasses.merge([segment(0, 2, "uk", -1, silence: 0.9)]).count, 1)
        XCTAssertEqual(TranscriptionPasses.merge([segment(0, 2, "uk", -2, silence: 0.6)]).count, 1)
        XCTAssertEqual(TranscriptionPasses.merge([
            segment(0, 2, "uk", -0.2), segment(0, 2, "ru", -0.2)
        ]).first?.lang, "uk")
    }

    func testInterruptedPassesResumeAndChangedInputsInvalidateCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("audio.m4a")
        try Data([1, 2, 3]).write(to: audio)
        let languages = ["uk", "ru", "en"]
        var calls: [String] = []
        do {
            _ = try await TranscriptionPasses.run(audioURL: audio, languages: languages, progressHandler: { _ in }) { options, _ in
                let language = try XCTUnwrap(options.language)
                calls.append(language)
                if language == "ru" { throw Interrupted.pass }
                return [self.segment(0, 2, language, -0.2)]
            }
            XCTFail("Expected the second language to fail")
        } catch Interrupted.pass {}
        XCTAssertEqual(calls, ["uk", "ru"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("pass_uk.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("pass_ru.json").path))

        calls = []
        _ = try await TranscriptionPasses.run(audioURL: audio, languages: languages, progressHandler: { _ in }) { options, _ in
            calls.append(try XCTUnwrap(options.language))
            return []
        }
        XCTAssertEqual(calls, ["ru", "en"])
        let cached = try await TranscriptionPasses.run(audioURL: audio, languages: languages, progressHandler: { _ in }) { _, _ in
            XCTFail("Completed passes must not invoke the model")
            throw Interrupted.pass
        }
        XCTAssertEqual(cached.first?.language, "uk")

        // The file can be moved with the meeting; absolute paths are not cache keys.
        let moved = root.appendingPathComponent("renamed")
        try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)
        for name in ["audio.m4a", "pass_uk.json", "pass_ru.json", "pass_en.json"] {
            try FileManager.default.moveItem(at: root.appendingPathComponent(name), to: moved.appendingPathComponent(name))
        }
        let movedAudio = moved.appendingPathComponent("audio.m4a")
        _ = try await TranscriptionPasses.run(audioURL: movedAudio, languages: ["uk"], progressHandler: { _ in }) { _, _ in
            XCTFail("A pinned language should reuse its completed pass after rename")
            throw Interrupted.pass
        }
        let cacheURL = moved.appendingPathComponent("pass_uk.json")
        for field in ["model", "backend", "options"] {
            var cache = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any])
            cache[field] = field == "options" ? Data("old options".utf8).base64EncodedString() : "old"
            try JSONSerialization.data(withJSONObject: cache).write(to: cacheURL)
            var reran = false
            _ = try await TranscriptionPasses.run(audioURL: movedAudio, languages: ["uk"], progressHandler: { _ in }) { _, _ in
                reran = true
                return []
            }
            XCTAssertTrue(reran, "Changed \(field) must invalidate the cache")
        }
        try Data("partial cache".utf8).write(to: cacheURL)
        calls = []
        _ = try await TranscriptionPasses.run(audioURL: movedAudio, languages: languages, progressHandler: { _ in }) { options, _ in
            calls.append(try XCTUnwrap(options.language))
            return []
        }
        XCTAssertEqual(calls, ["uk"])
        try Data([1, 2, 3, 4]).write(to: movedAudio)
        calls = []
        _ = try await TranscriptionPasses.run(audioURL: movedAudio, languages: languages, progressHandler: { _ in }) { options, _ in
            calls.append(try XCTUnwrap(options.language))
            return []
        }
        XCTAssertEqual(calls, languages)
    }

    func testPinnedDecodingAndNoSpeechProbability() throws {
        let options = TranscriptionPasses.options(language: "uk")
        XCTAssertEqual(options.language, "uk")
        XCTAssertFalse(options.detectLanguage)
        XCTAssertTrue(options.skipSpecialTokens)
        XCTAssertNil(options.promptTokens)
        XCTAssertEqual(options.concurrentWorkerCount, 1)
        let logits = try MLMultiArray(shape: [1, 1, 3], dataType: .float32)
        logits[0] = 1000
        logits[1] = 1000
        logits[2] = 1000
        XCTAssertEqual(SpeechProbabilityDecoder.probability(of: 1, in: logits), 1 / 3, accuracy: 0.00001)
        logits[1] = 1010
        XCTAssertGreaterThan(SpeechProbabilityDecoder.probability(of: 1, in: logits), 0.99)
    }

    @MainActor
    func testLanguagePreferencePersists() throws {
        let suite = "BetterMeetingLanguages.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(FileManager.default.temporaryDirectory.appendingPathComponent(suite), forKey: "outputFolder")
        let model = AppModel(defaults: defaults)
        XCTAssertEqual(model.transcriptionLanguage.languages, ["uk", "ru", "en"])
        model.transcriptionLanguage = .uk
        XCTAssertEqual(AppModel(defaults: defaults).transcriptionLanguage.languages, ["uk"])
    }

    func testRealMultilingualRecording() async throws {
        guard let path = ProcessInfo.processInfo.environment["BETTER_MEETING_TRANSCRIPTION_CHECK"] else {
            throw XCTSkip("Set BETTER_MEETING_TRANSCRIPTION_CHECK to a Ukrainian/Russian/English audio fixture")
        }
        let cache = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/model-check")
        let transcriber = LocalTranscriber(downloadBase: cache)
        let segments = try await transcriber.transcribe(audioURL: URL(fileURLWithPath: path)) { _ in }
        XCTAssertEqual(Set(segments.compactMap(\.language)), Set(["uk", "ru", "en"]))
        XCTAssertTrue(segments.allSatisfy { !$0.text.contains("<|") && $0.end > $0.start })
        for language in ["uk", "ru", "en"] {
            let passURL = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("pass_\(language).json")
            let cache = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: passURL)) as? [String: Any])
            let pass = try XCTUnwrap(cache["segments"] as? [[String: Any]])
            XCTAssertTrue(pass.contains { ($0["nospeech"] as? Double ?? 0) > 0 }, "No-speech probabilities must be computed, not hardcoded")
        }
    }

    func testTurboSilenceLimitation() async throws {
        guard ProcessInfo.processInfo.environment["BETTER_MEETING_TRANSCRIPTION_CHECK"] != nil else {
            throw XCTSkip("Set BETTER_MEETING_TRANSCRIPTION_CHECK to check the turbo model's silence behavior")
        }
        let cache = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/model-check")
        let transcriber = LocalTranscriber(downloadBase: cache)
        let silentFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: silentFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: silentFolder) }
        let silentAudio = silentFolder.appendingPathComponent("silence.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480000))
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData![0].initialize(repeating: 0, count: Int(buffer.frameLength))
        do {
            let file = try AVAudioFile(forWriting: silentAudio, settings: format.settings)
            try file.write(from: buffer)
        }
        let whisper = try await transcriber.prepare { _ in }
        // Expose the raw probability before the normal segment filter discards silence.
        let unfiltered = try await whisper.transcribe(
            audioPath: silentAudio.path,
            decodeOptions: DecodingOptions(
                language: "en", temperatureFallbackCount: 0, skipSpecialTokens: true,
                withoutTimestamps: true, compressionRatioThreshold: nil, logProbThreshold: nil,
                firstTokenLogProbThreshold: nil, noSpeechThreshold: nil, concurrentWorkerCount: 1
            )
        )
        let filtered = try await transcriber.transcribe(audioURL: silentAudio, languages: ["en"]) { _ in }
        let probability = try XCTUnwrap(unfiltered.flatMap(\.segments).map(\.noSpeechProb).max())
        XCTAssertTrue(probability.isFinite && probability >= 0 && probability <= 1)
        // Reported for OpenAI turbo too: github.com/openai/whisper/discussions/2363.
        XCTExpectFailure("The turbo model can assign silence a low no-speech probability and hallucinate text") {
            XCTAssertGreaterThan(probability, 0.6)
            XCTAssertTrue(filtered.isEmpty, "Silence must not produce a transcript")
        }
    }

    private func segment(_ start: Double, _ end: Double, _ language: String, _ score: Float, silence: Float = 0) -> ScoredSegment {
        ScoredSegment(start: start, end: end, text: "\(language) at \(start)", lang: language, score: score, nospeech: silence)
    }
}
