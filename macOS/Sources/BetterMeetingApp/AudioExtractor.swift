import AVFoundation
import Foundation

enum AudioExtractor {
    static func extract(from recordingURL: URL, to audioURL: URL) async throws {
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
        try await exporter.export(to: audioURL, as: .m4a)
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
