import XCTest
@testable import BetterMeetingApp

final class SpeechSettingsTests: XCTestCase {
    func testModelAndDecodingChangesInvalidatePasses() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let audio = folder.appendingPathComponent("audio.m4a")
        try Data([1]).write(to: audio)
        var settings = SpeechSettings()
        for index in 0..<4 {
            if index == 2 { settings.model = .small }
            if index == 3 { settings.temperature = 0.3; settings.fallbackCount = 2 }
            var ran = false
            _ = try await TranscriptionPasses.run(audioURL: audio, languages: ["en"], settings: settings, progressHandler: { _ in }) { options, _ in
                ran = true
                XCTAssertEqual(options.temperature, settings.temperature)
                XCTAssertEqual(options.temperatureFallbackCount, settings.fallbackCount)
                return []
            }
            XCTAssertEqual(ran, index != 1)
        }
        let segment = ScoredSegment(start: 0, end: 2, text: "Noise", lang: "en", score: -1.2, nospeech: 0.5)
        XCTAssertEqual(TranscriptionPasses.merge([segment]).count, 1)
        XCTAssertTrue(TranscriptionPasses.merge([segment], noSpeechThreshold: 0.4).isEmpty)
    }

    @MainActor
    func testSettingsPersistWithDefaultsAndMeeting() throws {
        let suite = "SpeechSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defaults.set(root, forKey: "outputFolder")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let model = AppModel(defaults: defaults)
        XCTAssertEqual(model.speechSettings.model, .turbo)
        model.speechSettings.model = .large
        model.speechSettings.noSpeechThreshold = 0.7
        XCTAssertEqual(AppModel(defaults: defaults).speechSettings, model.speechSettings)
        let date = Date()
        let folder = try MeetingArtifacts.createDirectory(in: root, title: "Options", recordedAt: date)
        XCTAssertNil(MeetingArtifacts.speechSettings(in: folder))
        try MeetingArtifacts.write(title: "Options", recordedAt: date, duration: 1, segments: [], speechSettings: model.speechSettings, to: folder)
        XCTAssertEqual(MeetingArtifacts.speechSettings(in: folder), model.speechSettings)
        let meeting = try XCTUnwrap(MeetingArtifacts.meetings(in: root).first)
        var changed = model.speechSettings
        changed.model = .small
        try MeetingArtifacts.replaceTranscript(for: meeting, duration: 1, segments: [], speechSettings: changed)
        XCTAssertEqual(MeetingArtifacts.speechSettings(in: folder), changed)
        changed.temperature = .nan
        XCTAssertThrowsError(try changed.validate())
        changed.temperature = .infinity
        XCTAssertThrowsError(try changed.validate())
        changed.temperature = 0
        changed.fallbackCount = -1
        XCTAssertThrowsError(try changed.validate())
    }
}
