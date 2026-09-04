import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class MeetingRecorder: NSObject, SCRecordingOutputDelegate {
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

    func start(to outputURL: URL) async throws {
        guard stream == nil else { throw RecorderError.alreadyRecording }
        guard CGPreflightScreenCaptureAccess() else { throw RecorderError.screenPermissionDenied }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecorderError.microphonePermissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID })
                ?? content.displays.first else {
            throw RecorderError.noDisplay
        }

        let ownBundleID = Bundle.main.bundleIdentifier
        let excludedApps = content.applications.filter { $0.bundleIdentifier == ownBundleID }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        let scale = min(1, 1440 / Double(display.width))
        configuration.width = max(2, Int(Double(display.width) * scale))
        configuration.height = max(2, Int(Double(display.height) * scale))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.captureMicrophone = true
        configuration.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = outputURL
        outputConfiguration.outputFileType = .mp4
        outputConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(
            configuration: outputConfiguration,
            delegate: self
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
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
            finishStart(with: .success(()))
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            finishStop(with: .success(()))
        }
    }

    nonisolated func recordingOutput(
        _ recordingOutput: SCRecordingOutput,
        didFailWithError error: any Error
    ) {
        Task { @MainActor in
            if startContinuation != nil {
                finishStart(with: .failure(error))
            } else {
                finishStop(with: .failure(error))
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

    private func cleanUp() {
        stream = nil
        recordingOutput = nil
    }
}

enum RecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case screenPermissionDenied
    case microphonePermissionDenied
    case noDisplay

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
            "No display is available to record."
        }
    }
}
