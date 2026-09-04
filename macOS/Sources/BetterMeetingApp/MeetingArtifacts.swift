import Foundation

struct TranscriptSegment: Codable, Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    let language: String?
}

struct MeetingManifest: Codable {
    let title: String
    let recordedAt: Date
    let duration: TimeInterval
    let recording: String
    let audio: String
    let transcript: String
    let segmentCount: Int
}

struct MeetingHistoryItem: Identifiable, Equatable, Sendable {
    let title: String
    let recordedAt: Date
    let duration: TimeInterval
    let folderURL: URL

    var id: URL { folderURL }
}

enum MeetingArtifacts {
    static func createDirectory(in root: URL, title: String, recordedAt: Date) throws -> URL {
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        let timestamp = folderDateFormatter.string(from: recordedAt)
        let safeTitle = sanitizedTitle(title)
        let baseName = "\(timestamp) — \(safeTitle)"
        var candidate = root.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(baseName) \(suffix)", isDirectory: true)
            suffix += 1
        }

        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
        return candidate
    }

    static func write(
        title: String,
        recordedAt: Date,
        duration: TimeInterval,
        segments: [TranscriptSegment],
        to folder: URL
    ) throws {
        let resolvedTitle = sanitizedTitle(title)
        let transcript = transcriptMarkdown(
            title: resolvedTitle,
            recordedAt: recordedAt,
            duration: duration,
            segments: segments
        )
        try transcript.write(
            to: folder.appendingPathComponent("transcript.md"),
            atomically: true,
            encoding: .utf8
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        let transcriptData = try encoder.encode(segments)
        try transcriptData.write(
            to: folder.appendingPathComponent("transcript.json"),
            options: .atomic
        )

        let manifest = MeetingManifest(
            title: resolvedTitle,
            recordedAt: recordedAt,
            duration: duration,
            recording: "recording.mp4",
            audio: "audio.m4a",
            transcript: "transcript.md",
            segmentCount: segments.count
        )
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(
            to: folder.appendingPathComponent("metadata.json"),
            options: .atomic
        )
    }

    static func recentTranscriptions(in root: URL, limit: Int = 5) -> [MeetingHistoryItem] {
        guard limit > 0 else { return [] }

        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return folders.compactMap { folder in
            let values = try? folder.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }

            let metadataURL = folder.appendingPathComponent("metadata.json")
            let transcriptURL = folder.appendingPathComponent("transcript.md")
            guard
                FileManager.default.fileExists(atPath: transcriptURL.path),
                let data = try? Data(contentsOf: metadataURL),
                let manifest = try? decoder.decode(MeetingManifest.self, from: data)
            else { return nil }

            return MeetingHistoryItem(
                title: manifest.title,
                recordedAt: manifest.recordedAt,
                duration: manifest.duration,
                folderURL: folder
            )
        }
        .sorted { $0.recordedAt > $1.recordedAt }
        .prefix(limit)
        .map { $0 }
    }

    static func transcriptMarkdown(
        title: String,
        recordedAt: Date,
        duration: TimeInterval,
        segments: [TranscriptSegment]
    ) -> String {
        let date = displayDateFormatter.string(from: recordedAt)
        var lines = [
            "# \(title)",
            "",
            "- Recorded: \(date)",
            "- Duration: \(Timecode.string(duration))",
            "- Recording: [recording.mp4](recording.mp4)",
            "",
            "## Transcript",
            "",
        ]

        if segments.isEmpty {
            lines.append("No speech was detected.")
        } else {
            lines.append(contentsOf: segments.map { segment in
                let language = segment.language.map { " [\($0)]" } ?? ""
                return "[\(Timecode.string(segment.start))]\(language) \(segment.text)"
            })
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func sanitizedTitle(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\n\r\t")
        let parts = title.components(separatedBy: invalid)
        let collapsed = parts
            .joined(separator: " ")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        let resolved = collapsed.isEmpty ? "Meeting" : collapsed
        return String(resolved.prefix(80))
    }

    private static let folderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}

enum Timecode {
    static func string(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
    }
}
