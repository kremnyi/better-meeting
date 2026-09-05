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
    @Published private(set) var microphoneLevel = 0.0
    @Published private(set) var systemAudioLevel = 0.0
    @Published private(set) var statusText = "Ready to record your display and audio."
    @Published private(set) var errorMessage: String?
    @Published private(set) var completedFolder: URL?
    @Published private(set) var outputRoot: URL
    @Published private(set) var privacyPermission: PrivacyPermission?
    @Published private(set) var processingFraction: Double?
    @Published private(set) var processingPhase: ProcessingPhase?
    @Published private(set) var transcriptionHistory: [MeetingHistoryItem] = []
    @Published var historyQuery = "" {
        didSet { searchHistory() }
    }
    @Published private(set) var searchingHistory = false
    @Published private(set) var unfinishedRecordings: [MeetingHistoryItem] = []
    @Published private(set) var modelReady = LocalTranscriber.cachedModelFolder() != nil
    @Published private(set) var modelSetupStatus = "Preparing speech model…"
    @Published private(set) var modelSetupFraction: Double?
    @Published private(set) var modelSetupError: String?
    private(set) var modelPreparationTask: Task<Void, Error>?
    @Published private(set) var cancellingTranscription = false
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
    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet { defaults.set(transcriptionLanguage.rawValue, forKey: "transcriptionLanguage") }
    }
    @Published var transcriptionHints: String {
        didSet { defaults.set(transcriptionHints, forKey: "transcriptionHints") }
    }
    @Published var candidateLanguages: [String] {
        didSet { defaults.set(candidateLanguages, forKey: "candidateLanguages") }
    }

    var transcriptionLanguages: [String] {
        transcriptionLanguage == .auto ? TranscriptionLanguage.candidates(from: candidateLanguages) : [transcriptionLanguage.rawValue]
    }

    private let defaults: UserDefaults
    private let recorder = MeetingRecorder()
    private let transcriber = LocalTranscriber()
    private var activeFolder: URL?
    private var recordedAt: Date?
    private var titleWasProvided = true
    private var timer: Timer?
    private var quitWhenFinished = false
    private(set) var processingTask: Task<Void, Never>?
    private(set) var historySearchTask: Task<Void, Never>?
    private var completedMeetings: [MeetingHistoryItem] = []
    private var lastTranscriptionOptions: (languages: [String], hints: String)?

    private var retryableMeeting: MeetingHistoryItem? {
        (unfinishedRecordings + completedMeetings).first { $0.folderURL == completedFolder }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        outputRoot = defaults.url(forKey: "outputFolder")
            ?? documents.appendingPathComponent("Better Meetings", isDirectory: true)
        selectedDisplayID = CGDirectDisplayID(clamping: defaults.integer(forKey: "displayID"))
        selectedMicrophoneID = defaults.string(forKey: "microphoneID") ?? ""
        captureResolution = CaptureResolution(rawValue: defaults.integer(forKey: "captureResolution")) ?? .pixels1440
        captureQuality = CaptureQuality(rawValue: defaults.integer(forKey: "captureQuality")) ?? .standard
        transcriptionLanguage = TranscriptionLanguage(rawValue: defaults.string(forKey: "transcriptionLanguage") ?? "") ?? .auto
        transcriptionHints = defaults.string(forKey: "transcriptionHints") ?? ""
        candidateLanguages = TranscriptionLanguage.candidates(from: defaults.stringArray(forKey: "candidateLanguages") ?? [])
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
            } else if retryableMeeting != nil {
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
        if state == .failed, retryableMeeting != nil {
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
        } else if state == .failed, let item = retryableMeeting {
            retryTranscription(item, languages: lastTranscriptionOptions?.languages, hints: lastTranscriptionOptions?.hints)
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
        guard !modelReady, state == .idle || state == .recording else { return }
        prepareSpeechModel { [transcriber] progress in
            _ = try await transcriber.prepare(progressHandler: progress)
        }
    }

    func prepareSpeechModel(
        _ prepare: @escaping (@escaping @Sendable (LocalTranscriptionProgress) -> Void) async throws -> Void
    ) {
        guard modelPreparationTask == nil else { return }
        modelReady = false
        modelSetupError = nil
        modelSetupFraction = nil
        modelSetupStatus = "Preparing speech model…"
        modelPreparationTask = Task {
            defer { modelPreparationTask = nil }
            do {
                try await prepare { [weak self] progress in
                    Task { @MainActor [weak self] in self?.updateModelSetupProgress(progress) }
                }
                modelReady = true
                modelSetupStatus = "Speech model ready"
            } catch {
                modelReady = false
                modelSetupError = error.localizedDescription
                modelSetupStatus = "Speech model unavailable"
                throw error
            }
        }
    }

    private func updateModelSetupProgress(_ progress: LocalTranscriptionProgress) {
        guard modelPreparationTask != nil else { return }
        switch progress {
        case .preparingModel:
            modelSetupStatus = "Checking speech model…"
            modelSetupFraction = nil
        case .downloadingModel(let fraction):
            modelSetupStatus = "Downloading speech model…"
            modelSetupFraction = fraction
        case .loadingModel:
            modelSetupStatus = "Loading speech model…"
            modelSetupFraction = nil
        case .transcribing:
            return
        }
        if state == .processing,
           [.preparingModel, .downloadingModel, .loadingModel].contains(processingPhase) {
            updateTranscriptionProgress(progress)
        }
    }

    func retryTranscription(_ item: MeetingHistoryItem, languages: [String]? = nil, hints: String? = nil) {
        guard state == .idle || state == .failed else { return }
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
        processingTask = Task {
            await MeetingNotifications.requestPermission()
            await finishRecording(
                stopCapture: false, replacing: item.needsTranscription ? nil : item,
                languages: languages, hints: hints
            )
        }
    }

    var canCancelTranscription: Bool {
        state == .processing && processingPhase != .finalizingRecording
            && processingPhase != .writingFiles && !cancellingTranscription
    }

    func cancelTranscription() {
        guard canCancelTranscription else { return }
        cancellingTranscription = true
        statusText = "Cancelling transcription…"
        processingTask?.cancel()
    }

    func dismissFailure() {
        guard state == .failed else { return }
        state = .idle
        errorMessage = nil
        privacyPermission = nil
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
        completedMeetings = meetings.filter { !$0.needsTranscription }
        unfinishedRecordings = meetings.filter(\.needsTranscription)
        searchHistory()
    }

    private func searchHistory() {
        historySearchTask?.cancel()
        let query = historyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchingHistory = false
            transcriptionHistory = Array(completedMeetings.prefix(10))
            return
        }
        let meetings = completedMeetings
        searchingHistory = true
        historySearchTask = Task.detached(priority: .userInitiated) { [weak self] in
            let matches = MeetingArtifacts.search(meetings, query: query)
            await self?.showSearchResults(matches)
        }
    }

    private func showSearchResults(_ matches: [MeetingHistoryItem]) {
        guard !Task.isCancelled else { return }
        transcriptionHistory = matches
        searchingHistory = false
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
                await MeetingNotifications.requestPermission()

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
        processingTask = Task {
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
        processingTask = Task {
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

    private func finishRecording(
        stopCapture: Bool, replacing: MeetingHistoryItem? = nil,
        languages: [String]? = nil, hints: String? = nil
    ) async {
        defer {
            processingTask = nil
            cancellingTranscription = false
        }
        let languages = languages ?? transcriptionLanguages
        let hints = hints ?? transcriptionHints
        lastTranscriptionOptions = (languages, hints)
        do {
            try Task.checkCancellation()
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
            try Task.checkCancellation()
            elapsed = Double(audio.length) / audio.fileFormat.sampleRate
            if replacing == nil {
                try MeetingArtifacts.writeMetadata(
                    title: meetingTitle, recordedAt: recordedAt, duration: elapsed,
                    titleWasProvided: titleWasProvided, to: folder
                )
            }

            if let preparation = modelPreparationTask {
                setProcessingPhase(.preparingModel, fraction: modelSetupFraction)
                statusText = modelSetupStatus
                try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: {
                    preparation.cancel()
                }
                try Task.checkCancellation()
            }
            let segments = try await transcriber.transcribe(
                audioURL: audioURL, languages: languages, hints: hints
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.updateTranscriptionProgress(progress)
                }
            }

            try Task.checkCancellation()
            setProcessingPhase(.writingFiles)
            if !titleWasProvided && replacing == nil {
                let generatedTitle = await Task.detached(priority: .utility) {
                    MeetingTitle.suggest(from: segments.map(\.text).joined(separator: "\n"))
                }.value
                if let generatedTitle {
                    folder = try MeetingArtifacts.renameDirectory(folder, title: generatedTitle, recordedAt: recordedAt)
                    activeFolder = folder
                    meetingTitle = generatedTitle
                }
            }
            if let replacing {
                try MeetingArtifacts.replaceTranscript(for: replacing, duration: elapsed, segments: segments)
            } else {
                try MeetingArtifacts.write(
                    title: meetingTitle,
                    recordedAt: recordedAt,
                    duration: elapsed,
                    segments: segments,
                    titleWasProvided: titleWasProvided,
                    to: folder
                )
            }

            completedFolder = folder
            modelReady = LocalTranscriber.cachedModelFolder() != nil
            modelSetupError = nil
            refreshHistory()
            await MeetingNotifications.post(
                title: transcriptionHistory.first(where: { $0.folderURL == folder })?.title ?? folder.lastPathComponent,
                folder: folder, failed: false
            )
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
            if Task.isCancelled {
                state = .idle
                statusText = "Transcription cancelled. Saved audio and completed passes are kept."
                processingPhase = nil
                processingFraction = nil
                activeFolder = nil
                recordedAt = nil
                meetingTitle = ""
                elapsed = 0
                refreshHistory()
                completeTermination(false)
                return
            }
            fail(error)
            if let activeFolder {
                await MeetingNotifications.post(title: meetingTitle, folder: activeFolder, failed: true)
            }
        }
    }

    private func startTimer(from startDate: Date) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsed = Date().timeIntervalSince(startDate)
                self?.microphoneLevel = self?.recorder.audioLevel(microphone: true) ?? 0
                self?.systemAudioLevel = self?.recorder.audioLevel(microphone: false) ?? 0
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        microphoneLevel = 0
        systemAudioLevel = 0
    }

    private func updateTranscriptionProgress(_ progress: LocalTranscriptionProgress) {
        guard !cancellingTranscription else { return }
        guard state == .processing else { return }

        switch progress {
        case .preparingModel:
            setProcessingPhase(.preparingModel)
        case .downloadingModel(let fraction):
            setProcessingPhase(.downloadingModel, fraction: fraction)
        case .loadingModel:
            setProcessingPhase(.loadingModel)
        case .transcribing(let fraction, let language, let pass, let total):
            setProcessingPhase(.transcribing, fraction: fraction)
            let name = TranscriptionLanguage(rawValue: language)?.label ?? language
            statusText = "Transcribing \(name) · pass \(pass) of \(total)…"
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
        if let activeFolder {
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
