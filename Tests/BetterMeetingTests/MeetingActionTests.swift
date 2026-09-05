import AppKit
import XCTest
@testable import BetterMeetingApp

final class MeetingActionTests: XCTestCase {
    func testRenamePreservesMeetingContents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_788_530_400)
        let folder = try MeetingArtifacts.createDirectory(in: root, title: "Original", recordedAt: date)
        try MeetingArtifacts.write(title: "Original", recordedAt: date, duration: 20, segments: [], to: folder)
        let body = "\r\n\r\nMy edited transcript.\r\n[recording.mp4](recording.mp4)\r\n"
        try ("# Original" + body).write(to: folder.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        let media = Data("recording data".utf8)
        try media.write(to: folder.appendingPathComponent("recording.mp4"))
        let transcriptJSON = try Data(contentsOf: folder.appendingPathComponent("transcript.json"))
        let metadataURL = folder.appendingPathComponent("metadata.json")
        var metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as? [String: Any])
        metadata["customField"] = "Keep this"
        try JSONSerialization.data(withJSONObject: metadata).write(to: metadataURL)
        let item = try XCTUnwrap(MeetingArtifacts.meetings(in: root).first)
        _ = try MeetingArtifacts.createDirectory(in: root, title: "Pricing Review", recordedAt: date)

        let renamed = try MeetingArtifacts.renameMeeting(item, to: " Pricing / Review ")

        XCTAssertTrue(renamed.lastPathComponent.hasSuffix(" — Pricing Review 2"))
        XCTAssertEqual(try String(contentsOf: renamed.appendingPathComponent("transcript.md"), encoding: .utf8), "# Pricing Review" + body)
        XCTAssertEqual(try Data(contentsOf: renamed.appendingPathComponent("recording.mp4")), media)
        XCTAssertEqual(try Data(contentsOf: renamed.appendingPathComponent("transcript.json")), transcriptJSON)
        let updated = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: renamed.appendingPathComponent("metadata.json"))) as? [String: Any])
        XCTAssertEqual(updated["title"] as? String, "Pricing Review")
        XCTAssertEqual(updated["titleWasProvided"] as? Bool, true)
        XCTAssertEqual(updated["customField"] as? String, "Keep this")
    }

    func testFailedRenameRestoresOriginalFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? fm.removeItem(at: root)
        }
        let date = Date()
        let folder = try MeetingArtifacts.createDirectory(in: root, title: "Original", recordedAt: date)
        try MeetingArtifacts.write(title: "Original", recordedAt: date, duration: 0, segments: [], to: folder)
        let item = try XCTUnwrap(MeetingArtifacts.meetings(in: root).first)
        let markdown = try Data(contentsOf: folder.appendingPathComponent("transcript.md"))
        let metadata = try Data(contentsOf: folder.appendingPathComponent("metadata.json"))
        XCTAssertThrowsError(try MeetingArtifacts.renameMeeting(item, to: " \n "))
        // File edits remain possible, but moving the folder must fail.
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        XCTAssertThrowsError(try MeetingArtifacts.renameMeeting(item, to: "New name"))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("transcript.md")), markdown)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("metadata.json")), metadata)
    }

    @MainActor
    func testCopyUsesSavedMarkdownAndKeepsClipboardOnReadFailure() throws {
        let suite = "BetterMeetingActions.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defaults.set(root, forKey: "outputFolder")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            pasteboard.releaseGlobally()
            try? FileManager.default.removeItem(at: root)
        }
        let date = Date()
        let folder = try MeetingArtifacts.createDirectory(in: root, title: "Copy me", recordedAt: date)
        try MeetingArtifacts.write(title: "Copy me", recordedAt: date, duration: 0, segments: [], to: folder)
        let model = AppModel(defaults: defaults)
        let item = try XCTUnwrap(model.transcriptionHistory.first)
        let markdownURL = folder.appendingPathComponent("transcript.md")
        let text = "# My notes\n\nAn edited transcript.\n"
        try text.write(to: markdownURL, atomically: true, encoding: .utf8)
        try model.copyTranscript(item, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), text)
        try FileManager.default.removeItem(at: markdownURL)
        XCTAssertThrowsError(try model.copyTranscript(item, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }
}
