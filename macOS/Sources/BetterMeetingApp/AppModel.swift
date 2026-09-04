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

enum ProcessingPhase: Equatable {
    case finalizingRecording
    case preparingAudio
    case preparingModel
    case downloadingModel
    case loadingModel
    case transcribing
    case writingFiles

    var stepText: String {
        "Step \(stepNumber) of 5"
    }

    var statusText: String {
        switch self {
        case .finalizingRecording: "Finalizing the recording…"
        case .preparingAudio: "Preparing audio for transcription…"
        case .preparingModel: "Checking the speech model…"
        case .downloadingModel: "Downloading the speech model…"
        case .loadingModel: "Loading the speech model…"
        case .transcribing: "Transcribing on this Mac…"
        case .writingFiles: "Writing transcript.md…"
        }
    }

    private var stepNumber: Int {
        switch self {
        case .finalizingRecording: 1
        case .preparingAudio: 2
        case .preparingModel, .downloadingModel, .loadingModel: 3
        case .transcribing: 4
        case .writingFiles: 5
        }
    }
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
    @Published private(set) var processingPhase: ProcessingPhase?
    @Published private(set) var transcriptionHistory: [MeetingHistoryItem] = []

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
        refreshHistory()
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
            if privacyPermission == .screenRecording {
                "Restart Better Meeting"
            } else if completedFolder != nil {
                "New recording"
            } else {
                "Try again"
            }
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

        if state == .recording {
            return "Stop here or from the macOS recording menu"
        }

        let microphoneReady = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if CGPreflightScreenCaptureAccess() && microphoneReady {
            return "Screen, system audio, and mic ready"
        }

        return "Permissions requested when recording"
    }

    var captureAccessSymbol: String {
        if state == .recording {
            return "stop.circle"
        }
        return privacyPermission == nil ? "shield" : "exclamationmark.shield"
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
            refreshHistory()
        }
    }

    func refreshHistory() {
        transcriptionHistory = MeetingArtifacts.recentTranscriptions(in: outputRoot)
    }

    func openHistoryFolder(_ item: MeetingHistoryItem) {
        NSWorkspace.shared.open(item.folderURL)
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
        processingPhase = nil
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
        processingPhase = nil
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
        beginProcessing()
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

        beginProcessing()
        Task {
            await finishRecording(stopCapture: false)
        }
    }

    private func beginProcessing() {
        if let recordedAt {
            elapsed = Date().timeIntervalSince(recordedAt)
        }
        stopTimer()
        state = .processing
        setProcessingPhase(.finalizingRecording)
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
            setProcessingPhase(.preparingAudio, fraction: 0)
            try await AudioExtractor.extract(from: recordingURL, to: audioURL) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard self?.processingPhase == .preparingAudio else { return }
                    self?.processingFraction = fraction
                }
            }

            let segments = try await transcriber.transcribe(audioURL: audioURL) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.updateTranscriptionProgress(progress)
                }
            }

            setProcessingPhase(.writingFiles)
            try MeetingArtifacts.write(
                title: meetingTitle,
                recordedAt: recordedAt,
                duration: elapsed,
                segments: segments,
                to: folder
            )

            completedFolder = folder
            refreshHistory()
            state = .complete
            statusText = "Video and transcript are ready."
            processingFraction = nil
            processingPhase = nil
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
            setProcessingPhase(.preparingModel)
        case .downloadingModel(let fraction):
            setProcessingPhase(.downloadingModel, fraction: fraction)
        case .loadingModel:
            setProcessingPhase(.loadingModel)
        case .transcribing(let fraction):
            setProcessingPhase(.transcribing, fraction: fraction)
        }
    }

    private func setProcessingPhase(_ phase: ProcessingPhase, fraction: Double? = nil) {
        processingPhase = phase
        statusText = phase.statusText
        processingFraction = fraction
    }

    private func fail(_ error: Error) {
        stopTimer()
        state = .failed
        statusText = "Couldn’t finish this recording."
        processingFraction = nil
        processingPhase = nil
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
