import SwiftUI

struct CaptureOptionsView: View {
    @EnvironmentObject private var model: AppModel
    @State var decodingPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if decodingPresented {
                Button { decodingPresented = false } label: {
                    Label("Options", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                DecodingSettingsView(settings: $model.speechSettings)
            } else {
                basicOptions
            }
        }
        .font(.callout)
        .controlSize(.small)
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }

    private var basicOptions: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text("Recording").font(.headline).gridCellColumns(2)
            }
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
            Divider().gridCellUnsizedAxes(.horizontal).padding(.vertical, 4)
            GridRow {
                Text("Transcription").font(.headline).gridCellColumns(2)
            }
            TranscriptionOptionsView(
                language: $model.transcriptionLanguage,
                candidates: $model.candidateLanguages, hints: $model.transcriptionHints,
                settings: $model.speechSettings, modelSelectionDisabled: model.modelPreparationTask != nil,
                showAdvanced: { decodingPresented = true }
            )
            .onChange(of: model.speechSettings.model) { model.speechModelChanged() }
            Divider().gridCellUnsizedAxes(.horizontal).padding(.vertical, 4)
            GridRow {
                Text("Files").font(.headline).gridCellColumns(2)
            }
            GridRow {
                Text("Save to")
                destinationButton
            }
            GridRow {
                Toggle("Include screenshots and screen text", isOn: $model.exportAfterRecording)
                    .help("After saving each transcript, export a bundle with screenshots and screen text into an artifacts folder.")
                    .gridCellColumns(2)
            }
        }
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

}

struct TranscriptionOptionsView: View {
    @Binding var language: TranscriptionLanguage
    @Binding var candidates: [String]
    @Binding var hints: String
    @Binding var settings: SpeechSettings
    var modelSelectionDisabled = false
    let showAdvanced: () -> Void

    var body: some View {
        Group {
            GridRow {
                Text("Model")
                Picker("Whisper model", selection: $settings.model) {
                    ForEach(SpeechModel.allCases, id: \.self) { model in
                        Text(model.label).tag(model)
                    }
                }
                .labelsHidden()
                .disabled(modelSelectionDisabled)
                .help(settings.model.detail + " Downloads once, then works offline.")
            }
            GridRow {
                Text("Language")
                Picker("Transcription language", selection: $language) {
                    ForEach(TranscriptionLanguage.allCases, id: \.self) { language in
                        Text(language.label).tag(language)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .help("Auto runs each candidate language separately, then merges by confidence")
            }
            if language == .auto {
                GridRow {
                    Text("Languages to detect")
                    Menu(candidates.joined(separator: ", ").uppercased()) {
                        ForEach(TranscriptionLanguage.allCases.filter { $0 != .auto }, id: \.self) { language in
                            Toggle(language.label, isOn: Binding(
                                get: { candidates.contains(language.rawValue) },
                                set: { selected in
                                    if selected { candidates.append(language.rawValue) }
                                    else { candidates.removeAll { $0 == language.rawValue } }
                                }
                            ))
                            .disabled(candidates == [language.rawValue])
                        }
                    }
                    .help("One pass per selected language. Fewer languages finish sooner.")
                }
            }
            GridRow {
                Text("Vocabulary")
                TextField("Names and terms (optional)", text: $hints)
                    .textFieldStyle(.roundedBorder)
                    .help("Comma-separated names, companies, or technical terms to help Whisper recognize them")
            }
            GridRow {
                Button("Advanced…", action: showAdvanced)
                    .gridCellColumns(2)
            }
        }
    }
}

struct RetranscriptionView: View {
    let meeting: MeetingHistoryItem
    @State var language: TranscriptionLanguage
    @State var candidates: [String]
    @State var hints: String
    @State var settings: SpeechSettings
    @State var decodingPresented = false
    let start: ([String], String, SpeechSettings) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if decodingPresented {
                Button { decodingPresented = false } label: {
                    Label("Transcription options", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                DecodingSettingsView(settings: $settings)
            } else {
                Text("Re-transcribe meeting").font(.headline)
                Text(meeting.title).lineLimit(2)
                Text("Replaces the saved transcript, including edits, only after processing succeeds. The meeting name stays the same.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    TranscriptionOptionsView(
                        language: $language, candidates: $candidates, hints: $hints, settings: $settings,
                        showAdvanced: { decodingPresented = true }
                    )
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Re-transcribe") {
                    dismiss()
                    start(language == .auto ? candidates : [language.rawValue], hints, settings)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.small)
        .padding(20)
        .frame(width: 360)
    }
}

struct DecodingSettingsView: View {
    @Binding var settings: SpeechSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Advanced transcription").font(.headline)
                Text("These settings control transcription retries and filtering.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                option("Temperature", value: $settings.temperature, range: 0...1,
                       help: "Higher values allow more varied wording; zero uses greedy decoding.")
                GridRow {
                    Text("Fallback attempts")
                    Stepper(value: $settings.fallbackCount, in: 0...10) {
                        Text("\(settings.fallbackCount)").monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                        .frame(width: 76)
                        .accessibilityLabel("Fallback attempts")
                        .help("Retries when decoding fails the quality thresholds. Zero disables retries.")
                }
                option("Temperature increase", value: $settings.fallbackIncrement, range: 0...1,
                       help: "Temperature increase for each retry.")
                option("No-speech threshold", value: $settings.noSpeechThreshold, range: 0...1,
                       help: "A segment is treated as silence when its no-speech probability exceeds this and its log probability is below the threshold.")
                option("Log probability threshold", value: $settings.logProbThreshold, range: -5...0,
                       help: "Average token log probability below this triggers a retry, or silence removal when the no-speech threshold is also exceeded.")
                option("Repetition threshold", value: $settings.compressionRatioThreshold, range: 1...5,
                       help: "Compression ratio above this triggers a retry for repetitive output.")
            }
            Button("Restore Defaults") {
                let model = settings.model
                settings = SpeechSettings()
                settings.model = model
            }
        }
        .controlSize(.small)
    }

    private func option(_ title: String, value: Binding<Float>, range: ClosedRange<Float>, help: String) -> some View {
        GridRow {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Stepper(value: value, in: range, step: 0.1) {
                Text(value.wrappedValue, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: 76)
            .accessibilityLabel(title)
            .help(help)
        }
    }
}
