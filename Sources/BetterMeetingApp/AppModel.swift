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
    @Published private(set) var statusText = "Ready to record your display and audio."
    @Published private(set) var errorMessage: String?
    @Published private(set) var completedFolder: URL?
    @Published private(set) var outputRoot: URL
    @Published private(set) var privacyPermission: PrivacyPermission?
    @Published private(set) var processingFraction: Double?
    @Published private(set) var processingPhase: ProcessingPhase?
    @Published private(set) var transcriptionHistory: [MeetingHistoryItem] = []
    @Published private(set) var unfinishedRecordings: [MeetingHistoryItem] = []
    @Published private(set) var modelReady = LocalTranscriber.cachedModelFolder() != nil
    @Published private(set) var displays: [(id: CGDirectDisplayID, name: String)] = []
    @Published private(set) var microphones: [AVCaptureDevice] = []
    @Published var selectedDisplayID: CGDirectDisplayID {
        didSet { defaults.set(Int(selectedDisplayID), forKey: "displayID") }
    }
    @Published var selectedMicrophoneID: String {
        didSet { defaults.set(selectedMicrophoneID, forKey: "microphoneID") }
    }
    @Published var captureResolution: CaptureResolution {
        didSet { defaults.set(captureResolution.rawValue, forKey: "captureResolution") }
    }
    @Published var captureQuality: CaptureQuality {
        didSet { defaults.set(captureQuality.rawValue, forKey: "captureQuality") }
    }

    private let defaults: UserDefaults
    private let recorder = MeetingRecorder()
    private let transcriber = LocalTranscriber()
    private var activeFolder: URL?
    private var recordedAt: Date?
    private var titleWasProvided = true
    private var timer: Timer?
    private var preparingModelOnly = false
    private var quitWhenFinished = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        outputRoot = defaults.url(forKey: "outputFolder")
            ?? documents.appendingPathComponent("Better Meetings", isDirectory: true)
        selectedDisplayID = CGDirectDisplayID(clamping: defaults.integer(forKey: "displayID"))
        selectedMicrophoneID = defaults.string(forKey: "microphoneID") ?? ""
        captureResolution = CaptureResolution(rawValue: defaults.integer(forKey: "captureResolution")) ?? .pixels1440
        captureQuality = CaptureQuality(rawValue: defaults.integer(forKey: "captureQuality")) ?? .standard
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
        case .preparing: "Preparing…"
        case .processing: "Transcribing…"
        case .idle: "Start recording"
        case .failed:
            if privacyPermission == .screenRecording {
                "Restart Better Meeting"
            } else if preparingModelOnly {
                "Retry model setup"
            } else if unfinishedRecordings.contains(where: { $0.folderURL == completedFolder }) {
                "Retry transcription"
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
        if state == .failed, preparingModelOnly || unfinishedRecordings.contains(where: { $0.folderURL == completedFolder }) {
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
        } else if state == .failed, preparingModelOnly {
            prepareSpeechModel()
        } else if state == .failed, let folder = completedFolder,
                  let item = unfinishedRecordings.first(where: { $0.folderURL == folder }) {
            retryTranscription(item)
        } else if state == .idle || state == .failed {
            startRecording()
        }
    }

    func refreshInputs() {
        displays = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return (number.uint32Value, screen.localizedName)
        }
        microphones = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified
        ).devices
    }

    func prepareSpeechModel() {
        guard state == .idle || state == .failed else { return }
        preparingModelOnly = true
        errorMessage = nil
        privacyPermission = nil
        completedFolder = nil
        state = .preparing
        setProcessingPhase(.preparingModel)
        Task {
            do {
                try await transcriber.prepare { [weak self] progress in
                    Task { @MainActor [weak self] in self?.updateTranscriptionProgress(progress) }
                }
                modelReady = true
                preparingModelOnly = false
                processingPhase = nil
                processingFraction = nil
                state = .idle
                statusText = "Speech model ready on this Mac."
            } catch {
                fail(error)
            }
        }
    }

    func retryTranscription(_ item: MeetingHistoryItem) {
        guard state == .idle || state == .failed else { return }
        preparingModelOnly = false
        activeFolder = item.folderURL
        completedFolder = nil
        recordedAt = item.recordedAt
        meetingTitle = item.title
        titleWasProvided = item.titleWasProvided
        elapsed = item.duration
        errorMessage = nil
        privacyPermission = nil
        state = .processing
        setProcessingPhase(.preparingAudio)
        Task { await finishRecording(stopCapture: false) }
    }

    func dismissFailure() {
        guard state == .failed else { return }
        state = .idle
        errorMessage = nil
        privacyPermission = nil
        preparingModelOnly = false
        meetingTitle = ""
        refreshHistory()
    }

    func terminationReply() -> NSApplication.TerminateReply {
        guard state == .recording || state == .processing || state == .preparing else {
            return .terminateNow
        }
        let alert = NSAlert()
        if state == .preparing {
            alert.messageText = "Setup is still running"
            alert.informativeText = "Wait for setup to finish before quitting."
            alert.addButton(withTitle: "Keep open")
            alert.runModal()
            return .terminateCancel
        }
        alert.messageText = state == .recording ? "Finish this recording and quit?" : "Quit when transcription finishes?"
        alert.informativeText = "Better Meeting will stay open until the recording and transcript are saved."
        alert.addButton(withTitle: state == .recording ? "Finish and quit" : "Wait and quit")
        alert.addButton(withTitle: "Keep open")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        // Processing may finish while the native confirmation is open.
        guard state == .recording || state == .processing else {
            return state == .idle ? .terminateNow : .terminateCancel
        }
        quitWhenFinished = true
        if state == .recording { stopRecording() }
        return .terminateLater
    }

    func setOutputFolder(_ url: URL) {
        outputRoot = url
        defaults.set(url, forKey: "outputFolder")
        refreshHistory()
    }

    private func completeTermination(_ success: Bool) {
        if quitWhenFinished {
            quitWhenFinished = false
            NSApp.reply(toApplicationShouldTerminate: success)
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
            setOutputFolder(url)
        }
    }

    func refreshHistory() {
        let meetings = MeetingArtifacts.meetings(in: outputRoot)
        transcriptionHistory = Array(meetings.filter { !$0.needsTranscription }.prefix(10))
        unfinishedRecordings = meetings.filter(\.needsTranscription)
    }

    func copyTranscript(_ meeting: MeetingHistoryItem, to pasteboard: NSPasteboard = .general) throws {
        let text = try String(contentsOf: meeting.folderURL.appendingPathComponent("transcript.md"), encoding: .utf8)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { throw MeetingActionError.clipboardUnavailable }
    }

    func renameMeeting(_ meeting: MeetingHistoryItem) {
        let alert = NSAlert()
        alert.messageText = "Rename meeting"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        nameField.stringValue = meeting.title
        nameField.setAccessibilityLabel("Meeting name")
        alert.accessoryView = nameField
        alert.window.initialFirstResponder = nameField
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let folder = try MeetingArtifacts.renameMeeting(meeting, to: nameField.stringValue)
            if completedFolder == meeting.folderURL { completedFolder = folder }
        } catch {
            NSAlert(error: error).runModal()
        }
        refreshHistory()
    }

    func openMeetingsFolder() {
        if !FileManager.default.fileExists(atPath: outputRoot.path) {
            try? FileManager.default.createDirectory(
                at: outputRoot,
                withIntermediateDirectories: true
            )
        }
        NSWorkspace.shared.open(outputRoot)
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

    private func startRecording() {
        preparingModelOnly = false
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
        titleWasProvided = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

                activeFolder = folder
                recordedAt = startedAt
                try await recorder.start(
                    to: recordingURL, displayID: selectedDisplayID, microphoneID: selectedMicrophoneID,
                    resolution: captureResolution, quality: captureQuality
                )
                state = .recording
                statusText = "Recording the selected display, system audio, and microphone."
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
            guard var folder = activeFolder, let recordedAt else {
                throw AppError.missingRecording
            }

            if stopCapture {
                try await recorder.stop()
            }

            let recordingURL = folder.appendingPathComponent("recording.mp4")
            let audioURL = folder.appendingPathComponent("audio.m4a")
            setProcessingPhase(.preparingAudio, fraction: 0)
            if ((try? AVAudioFile(forReading: audioURL).length) ?? 0) == 0 {
                try await AudioExtractor.extract(from: recordingURL, to: audioURL) { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        guard self?.processingPhase == .preparingAudio else { return }
                        self?.processingFraction = fraction
                    }
                }
            }
            let audio = try AVAudioFile(forReading: audioURL)
            elapsed = Double(audio.length) / audio.fileFormat.sampleRate
            try MeetingArtifacts.writeMetadata(
                title: meetingTitle, recordedAt: recordedAt, duration: elapsed,
                titleWasProvided: titleWasProvided, to: folder
            )

            let segments = try await transcriber.transcribe(audioURL: audioURL) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.updateTranscriptionProgress(progress)
                }
            }

            setProcessingPhase(.writingFiles)
            if !titleWasProvided {
                let generatedTitle = await Task.detached(priority: .utility) {
                    MeetingTitle.suggest(from: segments.map(\.text).joined(separator: "\n"))
                }.value
                if let generatedTitle {
                    folder = try MeetingArtifacts.renameDirectory(folder, title: generatedTitle, recordedAt: recordedAt)
                    activeFolder = folder
                    meetingTitle = generatedTitle
                }
            }
            try MeetingArtifacts.write(
                title: meetingTitle,
                recordedAt: recordedAt,
                duration: elapsed,
                segments: segments,
                titleWasProvided: titleWasProvided,
                to: folder
            )

            completedFolder = folder
            modelReady = true
            refreshHistory()
            elapsed = 0
            state = .idle
            statusText = "Ready to record your display and audio."
            errorMessage = nil
            privacyPermission = nil
            processingFraction = nil
            processingPhase = nil
            activeFolder = nil
            self.recordedAt = nil
            meetingTitle = ""
            completeTermination(true)
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
        guard state == .processing || (state == .preparing && preparingModelOnly) else { return }

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
        if let activeFolder, !preparingModelOnly {
            completedFolder = activeFolder
        }
        refreshHistory()
        completeTermination(false)

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
