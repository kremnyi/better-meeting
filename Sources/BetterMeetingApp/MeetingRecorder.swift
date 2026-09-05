import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class MeetingRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    var onUnexpectedStop: ((Error?) -> Void)?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var stopContinuation: CheckedContinuation<Void, Error>?

    func requestPermissions() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw RecorderError.screenPermissionDenied
        }

        let microphoneAllowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneAllowed = true
        case .notDetermined:
            microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            microphoneAllowed = false
        @unknown default:
            microphoneAllowed = false
        }
        guard microphoneAllowed else { throw RecorderError.microphonePermissionDenied }
    }

    func start(
        to outputURL: URL, displayID: CGDirectDisplayID, microphoneID: String,
        resolution: CaptureResolution, quality: CaptureQuality
    ) async throws {
        guard stream == nil else { throw RecorderError.alreadyRecording }
        guard CGPreflightScreenCaptureAccess() else { throw RecorderError.screenPermissionDenied }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError.microphonePermissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        let captureDisplayID = displayID == 0 ? CGMainDisplayID() : displayID
        guard let display = content.displays.first(where: { $0.displayID == captureDisplayID }) else {
            throw RecorderError.noDisplay
        }
        let microphone = microphoneID.isEmpty
            ? AVCaptureDevice.default(for: .audio)
            : AVCaptureDevice(uniqueID: microphoneID)
        guard let microphone, microphone.hasMediaType(.audio), microphone.isConnected else {
            throw RecorderError.noMicrophone
        }

        let ownBundleID = Bundle.main.bundleIdentifier
        let excludedApps = content.applications.filter { $0.bundleIdentifier == ownBundleID }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        let configuration = Self.videoConfiguration(
            sourceSize: CGSize(
                width: filter.contentRect.width * CGFloat(filter.pointPixelScale),
                height: filter.contentRect.height * CGFloat(filter.pointPixelScale)
            ),
            resolution: resolution, quality: quality
        )
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.captureMicrophone = true
        configuration.microphoneCaptureDeviceID = microphone.uniqueID

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = outputURL
        outputConfiguration.outputFileType = .mp4
        outputConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(
            configuration: outputConfiguration,
            delegate: self
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addRecordingOutput(recordingOutput)

        self.stream = stream
        self.recordingOutput = recordingOutput

        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            Task {
                do {
                    try await stream.startCapture()
                } catch {
                    finishStart(with: .failure(error))
                }
            }
        }
    }

    static func videoConfiguration(
        sourceSize: CGSize, resolution: CaptureResolution, quality: CaptureQuality
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let scale = min(1, CGFloat(resolution.rawValue) / max(sourceSize.width, sourceSize.height))
        // H.264 needs even dimensions; keep the aspect ratio without upscaling.
        configuration.width = max(2, Int(sourceSize.width * scale) / 2 * 2)
        configuration.height = max(2, Int(sourceSize.height * scale) / 2 * 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(quality.rawValue))
        configuration.captureResolution = .best
        return configuration
    }

    func stop() async throws {
        guard let stream else { throw RecorderError.notRecording }

        try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            Task {
                do {
                    try await stream.stopCapture()
                } catch {
                    finishStop(with: .failure(error))
                }
            }
        }
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            guard recordingOutput === self.recordingOutput else { return }
            finishStart(with: .success(()))
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            guard recordingOutput === self.recordingOutput else { return }
            if stopContinuation != nil {
                finishStop(with: .success(()))
            } else {
                finishUnexpectedStop(with: nil)
            }
        }
    }

    nonisolated func recordingOutput(
        _ recordingOutput: SCRecordingOutput,
        didFailWithError error: any Error
    ) {
        Task { @MainActor in
            guard recordingOutput === self.recordingOutput else { return }
            if startContinuation != nil {
                finishStart(with: .failure(error))
            } else if stopContinuation != nil {
                finishStop(with: .failure(error))
            } else {
                finishUnexpectedStop(with: error)
            }
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            guard stream === self.stream else { return }
            let nsError = error as NSError
            let code = SCStreamError.Code(rawValue: nsError.code)
            let wasStoppedIntentionally = nsError.domain == SCStreamErrorDomain
                && (code == .userStopped || code == .systemStoppedStream)
            // The recording-output callback confirms the MP4 has finished writing.
            if wasStoppedIntentionally, startContinuation == nil { return }
            if startContinuation != nil {
                finishStart(with: .failure(error))
            } else if stopContinuation != nil {
                finishStop(with: .failure(error))
            } else {
                finishUnexpectedStop(with: error)
            }
        }
    }

    private func finishStart(with result: Result<Void, Error>) {
        guard let continuation = startContinuation else { return }
        startContinuation = nil
        if case .failure = result {
            cleanUp()
        }
        continuation.resume(with: result)
    }

    private func finishStop(with result: Result<Void, Error>) {
        guard let continuation = stopContinuation else { return }
        stopContinuation = nil
        cleanUp()
        continuation.resume(with: result)
    }

    private func finishUnexpectedStop(with error: Error?) {
        guard stream != nil else { return }
        cleanUp()
        onUnexpectedStop?(error)
    }

    private func cleanUp() {
        let previousStream = stream
        stream = nil
        recordingOutput = nil
        Task { try? await previousStream?.stopCapture() }
    }
}

enum CaptureResolution: Int, CaseIterable {
    case pixels1280 = 1280
    case pixels1440 = 1440
    case pixels1920 = 1920
    case pixels2560 = 2560

    var label: String { "\(rawValue) px" }
}

enum CaptureQuality: Int, CaseIterable {
    case compact = 5
    case standard = 10
    case smooth = 30

    // ponytail: use frame rate presets; custom bitrate needs a different recording pipeline.
    var label: String {
        switch self {
        case .compact: "Compact · 5 fps"
        case .standard: "Standard · 10 fps"
        case .smooth: "Smooth · 30 fps"
        }
    }
}

enum RecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case screenPermissionDenied
    case microphonePermissionDenied
    case noDisplay
    case noMicrophone

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "A meeting is already being recorded."
        case .notRecording:
            "There is no active recording to stop."
        case .screenPermissionDenied:
            "Screen recording access needs to be enabled or refreshed. Turn Better Meeting on in System Settings, then restart the app."
        case .microphonePermissionDenied:
            "Microphone access is off. Enable Better Meeting in System Settings → Privacy & Security → Microphone."
        case .noDisplay:
            "The selected display is unavailable. Choose a connected display in Capture options."
        case .noMicrophone:
            "The selected microphone is unavailable. Choose a connected microphone in Capture options."
        }
    }
}
