import AppKit
import AVFoundation
import Combine
import CoreGraphics
import Foundation

enum AppState: Equatable {
    case idle
    case preparing
    case recording
    case processing
    case complete
    case failed
}

@MainActor
final class AppModel: ObservableObject {
    @Published var meetingTitle = ""
    @Published private(set) var state: AppState = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var statusText = "Ready to record your main display and audio."
    @Published private(set) var errorMessage: String?
    @Published private(set) var completedFolder: URL?
    @Published private(set) var outputRoot: URL
    @Published private(set) var privacyPermission: PrivacyPermission?
    @Published private(set) var processingFraction: Double?

    private let recorder = MeetingRecorder()
    private let transcriber = LocalTranscriber()
    private var activeFolder: URL?
    private var recordedAt: Date?
    private var timer: Timer?

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        outputRoot = documents.appendingPathComponent("Better Meetings", isDirectory: true)
        recorder.onUnexpectedStop = { [weak self] error in
            self?.captureStoppedExternally(with: error)
        }
    }

    var elapsedText: String {
        Timecode.string(elapsed)
    }

    var primaryButtonTitle: String {
        switch state {
        case .recording: "Stop recording"
        case .complete: "Recording complete"
        case .preparing: "Preparing…"
        case .processing: "Transcribing…"
        case .idle: "Start recording"
        case .failed:
            privacyPermission == .screenRecording ? "Restart Better Meeting" : "Try again"
        }
    }

    var primaryButtonSymbol: String {
        if state == .recording {
            return "stop.fill"
        }
        if state == .failed, privacyPermission == .screenRecording {
            return "arrow.clockwise"
        }
        return "record.circle"
    }

    var captureAccessText: String {
        if let privacyPermission {
            return privacyPermission.accessNeededText
        }

        let microphoneReady = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if CGPreflightScreenCaptureAccess() && microphoneReady {
            return "Display, system audio, and microphone ready"
        }

        return "Permissions requested when recording"
    }

    var captureAccessSymbol: String {
        privacyPermission == nil ? "shield" : "exclamationmark.shield"
    }

    func primaryAction() {
        if state == .recording {
            stopRecording()
        } else if state == .failed, privacyPermission == .screenRecording {
            restartApplication()
        } else {
            startRecording()
        }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose where meetings are saved"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputRoot

        if panel.runModal() == .OK, let url = panel.url {
            outputRoot = url
        }
    }

    func openCompletedFolder() {
        guard let completedFolder else { return }
        NSWorkspace.shared.open(completedFolder)
    }

    func openCompletedTranscript() {
        guard let completedFolder else { return }
        let transcript = completedFolder.appendingPathComponent("transcript.md")
        if FileManager.default.fileExists(atPath: transcript.path) {
            NSWorkspace.shared.open(transcript)
        } else {
            NSWorkspace.shared.open(completedFolder)
        }
    }

    func openPrivacySettings() {
        guard let url = privacyPermission?.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func restartApplication() {
        statusText = "Restarting Better Meeting…"

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.fail(error)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func reset() {
        stopTimer()
        elapsed = 0
        state = .idle
        statusText = "Ready to record your main display and audio."
        errorMessage = nil
        completedFolder = nil
        privacyPermission = nil
        processingFraction = nil
        activeFolder = nil
        recordedAt = nil
        meetingTitle = ""
    }

    private func startRecording() {
        stopTimer()
        elapsed = 0
        state = .preparing
        statusText = "Checking screen and microphone access…"
        errorMessage = nil
        completedFolder = nil
        privacyPermission = nil
        processingFraction = nil
        activeFolder = nil
        recordedAt = nil

        let title = meetingTitle
        Task {
            do {
                try await recorder.requestPermissions()

                let startedAt = Date()
                let folder = try MeetingArtifacts.createDirectory(
                    in: outputRoot,
                    title: title,
                    recordedAt: startedAt
                )
                let recordingURL = folder.appendingPathComponent("recording.mp4")

                try await recorder.start(to: recordingURL)

                activeFolder = folder
                recordedAt = startedAt
                state = .recording
                statusText = "Recording main display, system audio, and microphone."
                startTimer(from: startedAt)
            } catch {
                fail(error)
            }
        }
    }

    private func stopRecording() {
        beginProcessing(status: "Finalizing the recording…")
        Task {
            await finishRecording(stopCapture: true)
        }
    }

    private func captureStoppedExternally(with error: Error?) {
        guard state == .recording else { return }

        if let error {
            fail(error)
            return
        }

        beginProcessing(status: "Stopped from macOS. Finalizing the recording…")
        Task {
            await finishRecording(stopCapture: false)
        }
    }

    private func beginProcessing(status: String) {
        if let recordedAt {
            elapsed = Date().timeIntervalSince(recordedAt)
        }
        stopTimer()
        state = .processing
        statusText = status
        processingFraction = nil
    }

    private func finishRecording(stopCapture: Bool) async {
        do {
            guard let folder = activeFolder, let recordedAt else {
                throw AppError.missingRecording
            }

            if stopCapture {
                try await recorder.stop()
            }

            let recordingURL = folder.appendingPathComponent("recording.mp4")
            let audioURL = folder.appendingPathComponent("audio.m4a")
            statusText = "Preparing audio…"
            try await AudioExtractor.extract(from: recordingURL, to: audioURL)

            let segments = try await transcriber.transcribe(audioURL: audioURL) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.updateTranscriptionProgress(progress)
                }
            }

            statusText = "Writing transcript.md…"
            processingFraction = nil
            try MeetingArtifacts.write(
                title: meetingTitle,
                recordedAt: recordedAt,
                duration: elapsed,
                segments: segments,
                to: folder
            )

            completedFolder = folder
            state = .complete
            statusText = "Video and transcript are ready."
            processingFraction = nil
        } catch {
            if let activeFolder {
                completedFolder = activeFolder
            }
            fail(error)
        }
    }

    private func startTimer(from startDate: Date) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsed = Date().timeIntervalSince(startDate)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateTranscriptionProgress(_ progress: LocalTranscriptionProgress) {
        guard state == .processing else { return }

        switch progress {
        case .preparingModel:
            statusText = "Preparing the speech model…"
            processingFraction = nil
        case .downloadingModel(let fraction):
            statusText = "Downloading the speech model…"
            processingFraction = fraction
        case .loadingModel:
            statusText = "Loading the speech model…"
            processingFraction = nil
        case .transcribing:
            statusText = "Transcribing on this Mac…"
            processingFraction = nil
        }
    }

    private func fail(_ error: Error) {
        stopTimer()
        state = .failed
        statusText = "Couldn’t finish this recording."
        processingFraction = nil
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

        switch error as? RecorderError {
        case .screenPermissionDenied:
            privacyPermission = .screenRecording
        case .microphonePermissionDenied:
            privacyPermission = .microphone
        default:
            privacyPermission = nil
        }
    }
}

enum PrivacyPermission: Equatable {
    case screenRecording
    case microphone

    var accessNeededText: String {
        switch self {
        case .screenRecording: "Enable screen access, then restart"
        case .microphone: "Microphone access needed"
        }
    }

    var settingsURL: URL? {
        let anchor = switch self {
        case .screenRecording: "Privacy_ScreenCapture"
        case .microphone: "Privacy_Microphone"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

enum AppError: LocalizedError {
    case missingRecording

    var errorDescription: String? {
        switch self {
        case .missingRecording:
            "The active recording folder is missing. Start a new recording."
        }
    }
}
