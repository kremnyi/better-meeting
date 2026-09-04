import AVFoundation
import Foundation

enum AudioExtractor {
    static func extract(
        from recordingURL: URL,
        to audioURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let temporaryURL = audioURL.deletingLastPathComponent()
            .appendingPathComponent(".audio-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let asset = AVURLAsset(url: recordingURL)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioExtractionError.cannotCreateExporter
        }

        exporter.shouldOptimizeForNetworkUse = false
        progressHandler(0)
        let progressTask = Task {
            for await state in exporter.states(updateInterval: 0.2) {
                guard case .exporting(let progress) = state else { continue }
                progressHandler(progress.fractionCompleted)
            }
        }
        defer { progressTask.cancel() }

        try await exporter.export(to: temporaryURL, as: .m4a)
        if FileManager.default.fileExists(atPath: audioURL.path) {
            _ = try FileManager.default.replaceItemAt(audioURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: audioURL)
        }
        progressHandler(1)
    }
}

enum AudioExtractionError: LocalizedError {
    case cannotCreateExporter

    var errorDescription: String? {
        switch self {
        case .cannotCreateExporter:
            "The recording does not contain audio that can be prepared for transcription."
        }
    }
}
