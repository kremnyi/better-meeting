import AVFoundation
import Foundation

enum AudioExtractor {
    static func extract(
        from recordingURL: URL,
        to audioURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        if FileManager.default.fileExists(atPath: audioURL.path) {
            try FileManager.default.removeItem(at: audioURL)
        }

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
            while !Task.isCancelled {
                progressHandler(Double(exporter.progress))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { progressTask.cancel() }

        try await exporter.export(to: audioURL, as: .m4a)
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
