import SwiftUI

struct TranscriptionOptionsView: View {
    @Binding var language: TranscriptionLanguage
    @Binding var candidates: [String]
    @Binding var hints: String
    @Binding var settings: SpeechSettings
    var modelSelectionDisabled = false
    @State private var advancedPresented = false

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
                    Text("Candidates")
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
                Text("Decoding")
                Button("Advanced…") { advancedPresented = true }
                    .popover(isPresented: $advancedPresented) {
                        DecodingSettingsView(settings: $settings)
                    }
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
    let start: ([String], String, SpeechSettings) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Re-transcribe meeting").font(.headline)
            Text(meeting.title).lineLimit(2)
            Text("Replaces the saved transcript, including edits, only after processing succeeds. The meeting name stays the same.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                TranscriptionOptionsView(language: $language, candidates: $candidates, hints: $hints, settings: $settings)
            }
            .controlSize(.small)
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
        .padding(20)
        .frame(width: 360)
    }
}

struct DecodingSettingsView: View {
    @Binding var settings: SpeechSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Whisper decoding").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                option("Temperature", value: $settings.temperature, range: 0...1,
                       help: "Higher values allow more varied wording; zero uses greedy decoding.")
                GridRow {
                    Text("Fallback attempts")
                    Stepper("\(settings.fallbackCount)", value: $settings.fallbackCount, in: 0...10)
                        .help("Retries when decoding fails the quality thresholds. Zero disables retries.")
                }
                option("Fallback increase", value: $settings.fallbackIncrement, range: 0...1,
                       help: "Temperature increase for each retry.")
                option("No-speech threshold", value: $settings.noSpeechThreshold, range: 0...1,
                       help: "A segment is treated as silence when its no-speech probability exceeds this and its log probability is below the threshold.")
                option("Log probability", value: $settings.logProbThreshold, range: -5...0,
                       help: "Average token log probability below this triggers a retry, or silence removal when the no-speech threshold is also exceeded.")
                option("Repetition threshold", value: $settings.compressionRatioThreshold, range: 1...5,
                       help: "Compression ratio above this triggers a retry for repetitive output.")
            }
            Button("Reset decoding defaults") {
                let model = settings.model
                settings = SpeechSettings()
                settings.model = model
            }
        }
        .padding(16)
        .frame(width: 360)
        .controlSize(.small)
    }

    private func option(_ title: String, value: Binding<Float>, range: ClosedRange<Float>, help: String) -> some View {
        GridRow {
            Text(title)
            Stepper(value: value, in: range, step: 0.1) {
                Text(value.wrappedValue, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit()
            }
            .accessibilityLabel(title)
            .help(help)
        }
    }
}
