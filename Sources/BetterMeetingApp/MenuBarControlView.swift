import AppKit
import SwiftUI

struct MenuBarControlView: View {
    @EnvironmentObject private var model: AppModel
    @State var captureOptionsPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            content
                .padding(12)

            Divider()

            HStack(spacing: 8) {
                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 304)
        .onAppear {
            model.refreshHistory()
            model.refreshInputs()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Better Meeting")
                .font(.headline)

            if model.state != .idle {
                Spacer()

                Label(model.state.label, systemImage: model.state.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(model.state.tint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            idleContent
        case .preparing:
            preparingContent
        case .recording:
            recordingContent
        case .processing:
            processingContent
        case .failed:
            failedContent
        }
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Meeting name (optional)", text: $model.meetingTitle)
                .textFieldStyle(.roundedBorder)

            Button {
                captureOptionsPresented.toggle()
            } label: {
                Label("Capture options", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.callout)
            .popover(isPresented: $captureOptionsPresented, arrowEdge: .trailing) {
                captureOptions
                    .padding(12)
                    .frame(width: 304)
            }

            primaryActionButton

            captureSummary

            if !model.modelReady {
                Button("Set up transcription", action: model.prepareSpeechModel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Text("Download the speech model before your first meeting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            historySection
        }
    }

    private var captureOptions: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text("Display")
                Picker("Display", selection: $model.selectedDisplayID) {
                    Text("Main display").tag(UInt32(0))
                    ForEach(model.displays, id: \.id) { display in
                        Text(display.name).tag(display.id)
                    }
                    if model.selectedDisplayID != 0 && !model.displays.contains(where: { $0.id == model.selectedDisplayID }) {
                        Text("Unavailable display").tag(model.selectedDisplayID)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            GridRow {
                Text("Microphone")
                Picker("Microphone", selection: $model.selectedMicrophoneID) {
                    Text("System default").tag("")
                    ForEach(model.microphones, id: \.uniqueID) { microphone in
                        Text(microphone.localizedName).tag(microphone.uniqueID)
                    }
                    if !model.selectedMicrophoneID.isEmpty && !model.microphones.contains(where: { $0.uniqueID == model.selectedMicrophoneID }) {
                        Text("Unavailable microphone").tag(model.selectedMicrophoneID)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            GridRow {
                Text("Resolution")
                Picker("Resolution", selection: $model.captureResolution) {
                    ForEach(CaptureResolution.allCases, id: \.self) { resolution in
                        Text(resolution.label).tag(resolution)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .help("Limits the video's longest edge without upscaling")
            }
            GridRow {
                Text("Frame rate")
                Picker("Frame rate", selection: $model.captureQuality) {
                    ForEach(CaptureQuality.allCases, id: \.self) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .help("Higher frame rates make motion smoother and use more storage")
            }
            GridRow {
                Text("Save to")
                destinationButton
            }
        }
        .controlSize(.small)
        .font(.callout)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.unfinishedRecordings.isEmpty {
                Menu("Finish saved recording (\(model.unfinishedRecordings.count))") {
                    ForEach(model.unfinishedRecordings) { item in
                        Button("\(item.title) · \(item.recordedAt.formatted(date: .abbreviated, time: .shortened))") {
                            model.retryTranscription(item)
                        }
                    }
                }
                .help("Retry transcription from a saved recording")
            }

            Text("Recent meetings")
                .font(.callout.weight(.medium))

            if model.transcriptionHistory.isEmpty {
                Text("Finished meetings will appear here. Open their folders in Finder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.transcriptionHistory) { item in
                            historyRow(item)

                            if item.id != model.transcriptionHistory.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.trailing, 16)
                }
                .frame(height: historyListHeight)
            }

            Button {
                model.openMeetingsFolder()
            } label: {
                Label("Open meetings folder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var historyListHeight: CGFloat {
        CGFloat(min(model.transcriptionHistory.count, 6)) * 44
    }

    private func historyRow(_ item: MeetingHistoryItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if item.folderURL == model.completedFolder {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("·")
                    }

                    Text(item.recordedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    Text("·")
                    Text(Timecode.string(item.duration))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                NSWorkspace.shared.open(item.folderURL)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            .accessibilityLabel("Show \(item.title) in Finder")
        }
        .frame(minHeight: 43)
    }

    private var destinationButton: some View {
        Button {
            model.chooseOutputFolder()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")

                Text(model.outputRoot.lastPathComponent)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .help(model.outputRoot.path)
        .accessibilityLabel("Save recordings to \(model.outputRoot.path)")
        .accessibilityHint("Choose a different folder")
    }

    private var preparingContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(model.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
            processingIndicator
                .accessibilityLabel(model.statusText)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }

    private var recordingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.elapsedText)
                .font(.system(size: 32, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(model.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            primaryActionButton

            captureSummary
        }
    }

    private var processingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.elapsedText)
                    .font(.title3.monospacedDigit())

                Text("recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.statusText)
                    .font(.callout)

                Spacer()

                if let phase = model.processingPhase {
                    Text(phase.stepText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            processingIndicator
                .tint(.signalCoral)
                .accessibilityLabel(model.statusText)
        }
    }

    @ViewBuilder
    private var processingIndicator: some View {
        if let fraction = model.processingFraction {
            HStack(spacing: 8) {
                ProgressView(value: fraction)

                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            .progressViewStyle(.linear)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var failedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = model.errorMessage {
                errorView(error)
            }

            primaryActionButton

            Button("Back to meetings", action: model.dismissFailure)
                .buttonStyle(.bordered)

            if model.privacyPermission != nil {
                captureSummary
            }
        }
    }

    private var primaryActionButton: some View {
        Button {
            model.primaryAction()
        } label: {
            Label(model.primaryButtonTitle, systemImage: model.primaryButtonSymbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.signalCoral)
    }

    private var captureSummary: some View {
        Label(model.captureAccessText, systemImage: model.captureAccessSymbol)
            .font(.caption)
            .foregroundStyle(model.privacyPermission == nil ? Color.secondary : Color.orange)
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

            if model.privacyPermission != nil || model.completedFolder != nil {
                HStack(spacing: 10) {
                    if model.privacyPermission != nil {
                        Button("Open System Settings") {
                            if let url = model.privacyPermission?.settingsURL {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }

                    if model.completedFolder != nil {
                        Button("Show saved files") {
                            if let folder = model.completedFolder {
                                NSWorkspace.shared.open(folder)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
