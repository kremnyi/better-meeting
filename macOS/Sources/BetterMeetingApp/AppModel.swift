import AppKit
import Combine
import Foundation

enum AppState: Equatable {
    case idle
    case preparing
    case recording
    case processing
    case complete
    case failed

    var locksInputs: Bool {
        self == .preparing || self == .recording || self == .processing
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var meetingTitle = ""
    @Published private(set) var state: AppState = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var statusText = "Choose a folder, then start recording."
    @Published private(set) var errorMessage: String?
    @Published private(set) var completedFolder: URL?
    @Published private(set) var outputRoot: URL

    private let recorder = MeetingRecorder()
    private let transcriber = LocalTranscriber()
    private var activeFolder: URL?
    private var recordedAt: Date?
    private var timer: Timer?

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        outputRoot = documents.appendingPathComponent("Better Meetings", isDirectory: true)
    }

    var elapsedText: String {
        Timecode.string(elapsed)
    }

    var primaryButtonTitle: String {
        switch state {
        case .recording: "Stop recording"
        case .complete: "Recording complete"
        case .preparing, .processing: "Please wait"
        case .idle, .failed: "Start recording"
        }
    }

    var primaryButtonSymbol: String {
        state == .recording ? "stop.fill" : "record.circle"
    }

    var canPerformPrimaryAction: Bool {
        state == .idle || state == .recording || state == .failed
    }

    func primaryAction() {
        if state == .recording {
            stopRecording()
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

    func reset() {
        stopTimer()
        elapsed = 0
        state = .idle
        statusText = "Choose a folder, then start recording."
        errorMessage = nil
        completedFolder = nil
        activeFolder = nil
        recordedAt = nil
        meetingTitle = ""
    }

    private func startRecording() {
        stopTimer()
        elapsed = 0
        state = .preparing
        statusText = "Requesting screen and microphone access…"
        errorMessage = nil
        completedFolder = nil
        activeFolder = nil
        recordedAt = nil

        let title = meetingTitle
        Task {
            do {
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
                statusText = "Recording the main display, meeting audio, and microphone."
                startTimer(from: startedAt)
            } catch {
                fail(error)
            }
        }
    }

    private func stopRecording() {
        if let recordedAt {
            elapsed = Date().timeIntervalSince(recordedAt)
        }
        stopTimer()
        state = .processing
        statusText = "Finishing the recording…"

        Task {
            do {
                guard let folder = activeFolder, let recordedAt else {
                    throw AppError.missingRecording
                }

                try await recorder.stop()

                let recordingURL = folder.appendingPathComponent("recording.mp4")
                let audioURL = folder.appendingPathComponent("audio.m4a")
                statusText = "Preparing audio for transcription…"
                try await AudioExtractor.extract(from: recordingURL, to: audioURL)

                statusText = "Transcribing locally. The first run downloads the speech model…"
                let segments = try await transcriber.transcribe(audioURL: audioURL)

                statusText = "Writing the meeting transcript…"
                try MeetingArtifacts.write(
                    title: meetingTitle,
                    recordedAt: recordedAt,
                    duration: elapsed,
                    segments: segments,
                    to: folder
                )

                completedFolder = folder
                state = .complete
                statusText = "The recording and Markdown transcript are ready."
            } catch {
                if let activeFolder {
                    completedFolder = activeFolder
                }
                fail(error)
            }
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

    private func fail(_ error: Error) {
        stopTimer()
        state = .failed
        statusText = "The recording could not be completed."
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
