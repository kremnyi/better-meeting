import AppKit
import AVFoundation
import CoreMedia
import Foundation
import SwiftUI
import XCTest
@testable import BetterMeetingApp

final class RecoveryTests: XCTestCase {
    func testUnfinishedAndLegacyRecordingsSurviveReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_788_530_400)
        let folder = try MeetingArtifacts.createDirectory(in: root, title: "Product / sync", recordedAt: date)
        XCTAssertTrue(MeetingArtifacts.meetings(in: root).isEmpty, "A failed start with no recording is not recoverable")
        try Data([1]).write(to: folder.appendingPathComponent("recording.mp4"))
        let pending = try XCTUnwrap(MeetingArtifacts.meetings(in: root).first)
        XCTAssertTrue(pending.needsTranscription)
        XCTAssertEqual(pending.title, "Product sync")
        XCTAssertEqual(pending.recordedAt, date)

        // A crash between transcript writes must not turn a pending meeting into a completed one.
        try "partial".write(to: folder.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        try "[]".write(to: folder.appendingPathComponent("transcript.json"), atomically: true, encoding: .utf8)
        XCTAssertTrue(try XCTUnwrap(MeetingArtifacts.meetings(in: root).first).needsTranscription)

        try MeetingArtifacts.write(title: pending.title, recordedAt: date, duration: 12, segments: [], to: folder)
        XCTAssertFalse(try XCTUnwrap(MeetingArtifacts.meetings(in: root).first).needsTranscription)

        // Completed metadata from earlier app versions has no completion flag.
        let metadataURL = folder.appendingPathComponent("metadata.json")
        var metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any])
        metadata.removeValue(forKey: "transcriptionComplete")
        metadata.removeValue(forKey: "titleWasProvided")
        try JSONSerialization.data(withJSONObject: metadata).write(to: metadataURL)
        XCTAssertFalse(try XCTUnwrap(MeetingArtifacts.meetings(in: root).first).needsTranscription)
        XCTAssertTrue(try XCTUnwrap(MeetingArtifacts.meetings(in: root).first).titleWasProvided)

        // Earlier failures wrote no metadata at all. Their raw recording is still discoverable.
        try FileManager.default.removeItem(at: metadataURL)
        let legacy = try XCTUnwrap(MeetingArtifacts.meetings(in: root).first)
        XCTAssertTrue(legacy.needsTranscription)
        XCTAssertEqual(legacy.title, "Product sync")
        XCTAssertEqual(legacy.recordedAt, date)
    }

    func testFailedExportKeepsExistingAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioURL = root.appendingPathComponent("audio.m4a")
        let original = Data("saved meeting audio".utf8)
        try original.write(to: audioURL)
        let corruptURL = root.appendingPathComponent("corrupt.mp4")
        try Data("incomplete recording".utf8).write(to: corruptURL)
        for recordingURL in [root.appendingPathComponent("missing.mp4"), corruptURL] {
            do {
                try await AudioExtractor.extract(from: recordingURL, to: audioURL) { _ in
                    XCTFail("Invalid recordings must be rejected before export starts")
                }
                XCTFail("Exporting an invalid recording must fail")
            } catch {
                XCTAssertEqual(try Data(contentsOf: audioURL), original)
            }
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path)
            .contains { $0.hasPrefix(".audio-") })
    }

    func testSuccessfulExportReplacesExistingAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = buffer.frameCapacity
        try XCTUnwrap(buffer.floatChannelData)[0].update(repeating: 0, count: Int(buffer.frameLength))
        do {
            let source = try AVAudioFile(forWriting: sourceURL, settings: format.settings)
            try source.write(from: buffer)
        }
        let audioURL = root.appendingPathComponent("audio.m4a")
        try Data("previous audio".utf8).write(to: audioURL)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await AudioExtractor.extract(from: sourceURL, to: audioURL) { _ in }
        }
        if case .success = await cancelled.result { XCTFail("Cancelled export must not replace saved audio") }
        XCTAssertEqual(try Data(contentsOf: audioURL), Data("previous audio".utf8))
        try await AudioExtractor.extract(from: sourceURL, to: audioURL) { _ in }
        XCTAssertGreaterThan(try AVAudioFile(forReading: audioURL).length, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path)
            .contains { $0.hasPrefix(".audio-") })
    }

    func testEmptyModelDirectoriesAreNotAReadyCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("\(name).mlmodelc"), withIntermediateDirectories: true)
        }
        XCTAssertFalse(LocalTranscriber.hasModelFiles(in: root))
    }

    @MainActor
    func testBackgroundModelSetupCanRetryWithoutTakingOverRecording() async throws {
        let suite = "BetterMeetingSetup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(FileManager.default.temporaryDirectory.appendingPathComponent(suite), forKey: "outputFolder")
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.meetingTitle = "Next meeting"
        var attempts = 0
        model.prepareSpeechModel { _ in
            attempts += 1
            throw URLError(.notConnectedToInternet)
        }
        let first = try XCTUnwrap(model.modelPreparationTask)
        model.prepareSpeechModel { _ in XCTFail("Setup must reuse the running task") }
        _ = await first.result
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.primaryButtonTitle, "Start recording")
        XCTAssertEqual(model.meetingTitle, "Next meeting")
        XCTAssertNil(model.errorMessage)
        XCTAssertNotNil(model.modelSetupError)
        XCTAssertFalse(model.modelReady)
        XCTAssertNil(model.modelPreparationTask)

        model.prepareSpeechModel { _ in attempts += 1 }
        try await model.modelPreparationTask?.value
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(model.modelReady)
        XCTAssertNil(model.modelSetupError)
        XCTAssertEqual(model.state, .idle)
        model.prepareSpeechModel()
        XCTAssertNil(model.modelPreparationTask, "A ready model needs no further setup")

        model.prepareSpeechModel { _ in try Task.checkCancellation() }
        let cancelled = try XCTUnwrap(model.modelPreparationTask)
        cancelled.cancel()
        _ = await cancelled.result
        XCTAssertFalse(model.modelReady)
        XCTAssertNil(model.modelPreparationTask)
        XCTAssertEqual(model.state, .idle)
    }

    @MainActor
    func testProcessingIconFramesAreDistinctTemplateImages() throws {
        let frames = BrandAssets.processingMenuBarFrames
        XCTAssertGreaterThan(frames.count, 1)
        let rendered = try frames.map { image in
            XCTAssertTrue(image.isTemplate, "The menu bar must adapt to light and dark appearances")
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            return try XCTUnwrap(image.tiffRepresentation)
        }
        XCTAssertEqual(Set(rendered).count, frames.count, "Every animation tick must change the image")
    }

    @MainActor
    func testHistoryRemainsSearchableDuringProcessingAndCancellationShowsRecovery() async throws {
        let suite = "BetterMeetingProcessing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defaults.set(root, forKey: "outputFolder")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let date = Date(timeIntervalSince1970: 1_788_530_400)
        let saved = try MeetingArtifacts.createDirectory(in: root, title: "Product sync", recordedAt: date)
        try MeetingArtifacts.write(title: "Product sync", recordedAt: date, duration: 720, segments: [], to: saved)
        let pending = try MeetingArtifacts.createDirectory(in: root, title: "Release planning", recordedAt: date)
        try Data([1]).write(to: pending.appendingPathComponent("recording.mp4"))
        _ = NSApplication.shared
        let model = AppModel(defaults: defaults)
        let item = try XCTUnwrap(model.unfinishedRecordings.first)
        model.retryTranscription(item)
        let processing = try XCTUnwrap(model.processingTask)
        XCTAssertEqual(model.state, .processing)
        let view = NSHostingView(rootView: MenuBarControlView().environmentObject(model)
            .environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        view.layoutSubtreeIfNeeded()
        func searchField(in view: NSView) -> NSSearchField? {
            (view as? NSSearchField) ?? view.subviews.lazy.compactMap { searchField(in: $0) }.first
        }
        let field = try XCTUnwrap(searchField(in: view), "Processing must keep the history search visible")
        XCTAssertTrue(field.isEnabled)
        if let path = ProcessInfo.processInfo.environment["BETTER_MEETING_PANELS_PREVIEW_PATH"] {
            try writePreview(view, to: URL(fileURLWithPath: path).appendingPathComponent("processing.png"))
        }
        field.stringValue = "Product"
        field.sendAction(field.action, to: field.target)
        XCTAssertEqual(model.historyQuery, "Product")
        model.cancelTranscription()
        await processing.value
        await model.historySearchTask?.value
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.transcriptionHistory.map(\.title), ["Product sync"])
        XCTAssertEqual(model.unfinishedRecordings.first?.folderURL.resolvingSymlinksInPath(), pending.resolvingSymlinksInPath())
        if let path = ProcessInfo.processInfo.environment["BETTER_MEETING_PANELS_PREVIEW_PATH"] {
            try writePreview(view, to: URL(fileURLWithPath: path).appendingPathComponent("cancelled.png"))
        }
    }

    @MainActor
    func testPopoversDoNotResizeMenu() throws {
        let suite = "BetterMeetingLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(FileManager.default.temporaryDirectory.appendingPathComponent(suite), forKey: "outputFolder")
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = NSApplication.shared
        let model = AppModel(defaults: defaults)
        let closed = NSHostingView(rootView: MenuBarControlView().environmentObject(model))
        let presented = NSHostingView(rootView: MenuBarControlView(captureOptionsPresented: true).environmentObject(model))
        let about = NSHostingView(rootView: MenuBarControlView(aboutPresented: true).environmentObject(model))
        XCTAssertGreaterThan(closed.fittingSize.height, 0)
        XCTAssertEqual(presented.fittingSize, closed.fittingSize)
        XCTAssertEqual(about.fittingSize, closed.fittingSize)
    }

    @MainActor
    func testOptionsAndAboutLayouts() throws {
        let suite = "BetterMeetingPanelLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(FileManager.default.temporaryDirectory.appendingPathComponent(suite), forKey: "outputFolder")
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = NSApplication.shared
        let model = AppModel(defaults: defaults)
        var panels: [(String, AnyView, CGFloat)] = [
            ("options", AnyView(CaptureOptionsView()), 360),
            ("advanced", AnyView(CaptureOptionsView(decodingPresented: true)), 360)
        ]
        for (name, status): (String, ReleaseCheck.Status) in [
            ("unchecked", .unchecked), ("checking", .checking), ("current", .current),
            ("available", .available("0.3.9")), ("failed", .failed)
        ] {
            panels.append(("about-\(name)", AnyView(AboutView(version: "0.3.8", homebrewAvailable: true, status: status)), 304))
        }
        panels.append(("about-download", AnyView(AboutView(
            version: "0.3.8", homebrewAvailable: false, status: .available("0.3.9")
        )), 304))
        var aboutHeight: CGFloat?
        for (name, content, width) in panels {
            let view = NSHostingView(rootView: content.environmentObject(model)
                .environment(\.colorScheme, .light)
                .background(Color(nsColor: .windowBackgroundColor)))
            XCTAssertEqual(view.fittingSize.width, width, "\(name) must keep its panel width")
            XCTAssertGreaterThan(view.fittingSize.height, 0)
            if ["about-unchecked", "about-checking", "about-current", "about-failed"].contains(name) {
                if let aboutHeight { XCTAssertEqual(view.fittingSize.height, aboutHeight, "Checking and errors must not resize About") }
                else { aboutHeight = view.fittingSize.height }
            }
            if let path = ProcessInfo.processInfo.environment["BETTER_MEETING_PANELS_PREVIEW_PATH"] {
                let output = URL(fileURLWithPath: path).appendingPathComponent("\(name).png")
                try writePreview(view, to: output)
            }
        }
    }

    @MainActor
    func testSearchDoesNotResizeMenu() async throws {
        let suite = "BetterMeetingSearchLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        defaults.set(root, forKey: "outputFolder")
        for index in 0..<7 {
            let date = Date(timeIntervalSince1970: Double(index * 60))
            let folder = try MeetingArtifacts.createDirectory(in: root, title: "Meeting \(index)", recordedAt: date)
            try MeetingArtifacts.write(title: "Meeting \(index)", recordedAt: date, duration: 60, segments: [], to: folder)
        }
        _ = NSApplication.shared
        let model = AppModel(defaults: defaults)
        func size() -> NSSize {
            NSHostingView(rootView: MenuBarControlView().environmentObject(model)).fittingSize
        }
        let initial = size()
        let menu = NSHostingView(rootView: MenuBarControlView().environmentObject(model))
        menu.frame = NSRect(origin: .zero, size: initial)
        menu.layoutSubtreeIfNeeded()
        func searchField(in view: NSView) -> NSSearchField? {
            (view as? NSSearchField) ?? view.subviews.lazy.compactMap { searchField(in: $0) }.first
        }
        let field = try XCTUnwrap(searchField(in: menu))
        XCTAssertEqual(field.bounds.width, initial.width - 24, accuracy: 1, "Search must fill the padded content width")
        field.stringValue = "Meeting 1"
        field.sendAction(field.action, to: field.target)
        XCTAssertEqual(model.historyQuery, "Meeting 1")
        XCTAssertTrue(model.searchingHistory)
        XCTAssertEqual(size(), initial)
        await model.historySearchTask?.value
        XCTAssertEqual(model.transcriptionHistory.count, 1)
        XCTAssertEqual(size(), initial)
        model.historyQuery = "no such meeting"
        await model.historySearchTask?.value
        XCTAssertTrue(model.transcriptionHistory.isEmpty)
        XCTAssertEqual(size(), initial)
        let cell = try XCTUnwrap(field.cell as? NSSearchFieldCell)
        let clear = try XCTUnwrap(cell.cancelButtonCell)
        clear.performClick(field)
        XCTAssertEqual(model.historyQuery, "")
        XCTAssertEqual(model.transcriptionHistory.count, 7)
        XCTAssertEqual(size(), initial)
    }

    @MainActor
    func testSavedMeetingKeepsTheSameRowHeight() {
        _ = NSApplication.shared
        let item = MeetingHistoryItem(
            title: "2026-09-05 14.39.08", recordedAt: Date(timeIntervalSince1970: 1_788_611_948),
            duration: 34, folderURL: URL(fileURLWithPath: "/tmp/layout-preview"),
            needsTranscription: false, titleWasProvided: false
        )
        for saved in [false, true] {
            let row = NSHostingView(rootView: MenuBarControlView().historyRow(item, isSaved: saved, canEdit: true)
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 264))
            XCTAssertEqual(row.fittingSize.height, 47, "The saved indicator must not wrap meeting details")
        }
    }

    @MainActor
    func testRenderMenuBarPreview() throws {
        guard let path = ProcessInfo.processInfo.environment["BETTER_MEETING_PREVIEW_PATH"] else {
            throw XCTSkip("Set BETTER_MEETING_PREVIEW_PATH to render the menu with fictional meetings")
        }
        let suite = "BetterMeetingPreview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite).appendingPathComponent("Better Meetings")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }
        defaults.set(root, forKey: "outputFolder")
        for (index, title) in ["Product sync", "Release planning", "Design review"].enumerated() {
            let date = Date(timeIntervalSince1970: 1_788_530_400 - Double(index * 3_600))
            let folder = try MeetingArtifacts.createDirectory(in: root, title: title, recordedAt: date)
            try MeetingArtifacts.write(title: title, recordedAt: date, duration: Double(720 + index * 180), segments: [], to: folder)
        }
        _ = NSApplication.shared
        let model = AppModel(defaults: defaults)
        let view = NSHostingView(rootView: MenuBarControlView()
            .environmentObject(model)
            .environment(\.colorScheme, .light)
            .background(Color(nsColor: .windowBackgroundColor)))
        try writePreview(view, to: URL(fileURLWithPath: path))
    }

    @MainActor
    private func writePreview(_ view: NSView, to output: URL) throws {
        view.appearance = NSAppearance(named: .aqua)
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: output)
    }

    @MainActor
    func testPreferencesPersistAndHistoryKeepsOlderUnfinishedMeetings() throws {
        let suite = "BetterMeetingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        for index in 0..<12 {
            let date = Date(timeIntervalSince1970: Double(index * 60))
            let folder = try MeetingArtifacts.createDirectory(in: root, title: "Meeting \(index)", recordedAt: date)
            if index == 0 {
                try Data([1]).write(to: folder.appendingPathComponent("audio.m4a"))
            } else {
                try MeetingArtifacts.write(title: "Meeting \(index)", recordedAt: date, duration: 60, segments: [], to: folder)
            }
        }
        let model = AppModel(defaults: defaults)
        XCTAssertEqual(model.captureResolution, .pixels1440)
        XCTAssertEqual(model.captureQuality, .standard)
        model.setOutputFolder(root)
        model.selectedDisplayID = 42
        model.selectedMicrophoneID = "test-mic"
        model.captureResolution = .pixels1920
        model.captureQuality = .smooth
        let reopened = AppModel(defaults: defaults)
        XCTAssertEqual(reopened.outputRoot.path, root.path)
        XCTAssertEqual(reopened.selectedDisplayID, 42)
        XCTAssertEqual(reopened.selectedMicrophoneID, "test-mic")
        XCTAssertEqual(reopened.captureResolution, .pixels1920)
        XCTAssertEqual(reopened.captureQuality, .smooth)
        XCTAssertEqual(reopened.transcriptionHistory.count, 10)
        XCTAssertEqual(reopened.transcriptionHistory.first?.title, "Meeting 11")
        XCTAssertEqual(reopened.unfinishedRecordings.map(\.title), ["Meeting 0"])
        XCTAssertEqual(reopened.terminationReply(), .terminateNow)
        defaults.set(999, forKey: "captureResolution")
        defaults.set(999, forKey: "captureQuality")
        let invalidPreferences = AppModel(defaults: defaults)
        XCTAssertEqual(invalidPreferences.captureResolution, .pixels1440)
        XCTAssertEqual(invalidPreferences.captureQuality, .standard)
    }

    @MainActor
    func testVideoPresetsRespectSourceSizeAndFrameRate() {
        for resolution in CaptureResolution.allCases {
            for quality in CaptureQuality.allCases {
                for source in [CGSize(width: 3840, height: 2160), CGSize(width: 2160, height: 3840),
                               CGSize(width: 1025, height: 769), CGSize(width: 5120, height: 1440)] {
                    let configuration = MeetingRecorder.videoConfiguration(
                        sourceSize: source, resolution: resolution, quality: quality
                    )
                    let scale = min(1, CGFloat(resolution.rawValue) / max(source.width, source.height))
                    XCTAssertLessThanOrEqual(max(configuration.width, configuration.height), resolution.rawValue)
                    XCTAssertLessThanOrEqual(CGFloat(configuration.width), source.width)
                    XCTAssertLessThanOrEqual(CGFloat(configuration.height), source.height)
                    XCTAssertEqual(configuration.width % 2, 0)
                    XCTAssertEqual(configuration.height % 2, 0)
                    XCTAssertEqual(CGFloat(configuration.width), source.width * scale, accuracy: 2)
                    XCTAssertEqual(CGFloat(configuration.height), source.height * scale, accuracy: 2)
                    XCTAssertEqual(CMTimeGetSeconds(configuration.minimumFrameInterval), 1 / Double(quality.rawValue), accuracy: 0.0001)
                }
            }
        }
    }

    @MainActor
    func testAudioMeterHandlesSilenceStereoAndClipping() throws {
        for interleaved in [false, true] {
            let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: interleaved))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100))
            buffer.frameLength = 100
            let channels = try XCTUnwrap(buffer.floatChannelData)
            for frame in 0..<100 {
                channels[0][frame * buffer.stride] = 0
                channels[1][frame * buffer.stride] = 0
            }
            XCTAssertEqual(MeetingRecorder.meterLevel(buffer), 0)
            for frame in 0..<100 { channels[1][frame * buffer.stride] = 0.1 }
            XCTAssertEqual(MeetingRecorder.meterLevel(buffer), 2.0 / 3, accuracy: 0.001)
            for frame in 0..<100 { channels[1][frame * buffer.stride] = 2 }
            XCTAssertEqual(MeetingRecorder.meterLevel(buffer), 1)
        }
        for commonFormat: AVAudioCommonFormat in [.pcmFormatInt16, .pcmFormatInt32] {
            let format = try XCTUnwrap(AVAudioFormat(commonFormat: commonFormat, sampleRate: 48_000, channels: 1, interleaved: false))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100))
            buffer.frameLength = 100
            buffer.int16ChannelData?[0].update(repeating: 16384, count: 100)
            buffer.int32ChannelData?[0].update(repeating: 1073741824, count: 100)
            XCTAssertEqual(MeetingRecorder.meterLevel(buffer), (20 * log10(0.5) + 60) / 60, accuracy: 0.001)
        }
    }

    @MainActor
    func testSearchFindsOlderTitlesAndEditedTranscripts() async throws {
        let suite = "BetterMeetingSearch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defaults.set(root, forKey: "outputFolder")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        var oldest: URL?
        for index in 0..<12 {
            let date = Date(timeIntervalSince1970: Double(index * 60))
            let title = index == 0 ? "Café planning" : "Meeting \(index)"
            let folder = try MeetingArtifacts.createDirectory(in: root, title: title, recordedAt: date)
            try MeetingArtifacts.write(title: title, recordedAt: date, duration: 0, segments: [], to: folder)
            if index == 0 { oldest = folder }
        }
        let model = AppModel(defaults: defaults)
        XCTAssertEqual(model.transcriptionHistory.count, 10)
        model.historyQuery = "cafe"
        await model.historySearchTask?.value
        XCTAssertEqual(model.transcriptionHistory.map(\.title), ["Café planning"])
        try "Edited notes about pricing".write(to: try XCTUnwrap(oldest).appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        model.historyQuery = "PRICING"
        await model.historySearchTask?.value
        XCTAssertEqual(model.transcriptionHistory.map(\.title), ["Café planning"])
        model.historyQuery = "missing"
        model.historyQuery = "  "
        await model.historySearchTask?.value
        XCTAssertEqual(model.transcriptionHistory.count, 10, "Cancelled search must not replace newer results")
        XCTAssertFalse(model.searchingHistory)
    }

    func testModelPreparationAcrossColdLaunches() async throws {
        guard let mode = ProcessInfo.processInfo.environment["BETTER_MEETING_MODEL_CHECK"] else {
            throw XCTSkip("Set BETTER_MEETING_MODEL_CHECK=prepare, then offline in a separate process to check the real model cache")
        }
        let cache = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/model-check")
        if mode == "offline" {
            XCTAssertNotNil(LocalTranscriber.cachedModelFolder(in: cache))
            URLProtocol.registerClass(OfflineRequests.self)
        }
        defer { URLProtocol.unregisterClass(OfflineRequests.self) }
        try await LocalTranscriber(downloadBase: cache).prepare { _ in }
        XCTAssertNotNil(LocalTranscriber.cachedModelFolder(in: cache))
    }
}

private final class OfflineRequests: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTFail("Cached model setup attempted a network request")
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
