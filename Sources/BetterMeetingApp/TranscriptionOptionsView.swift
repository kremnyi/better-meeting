import SwiftUI

struct TranscriptionOptionsView: View {
    @Binding var language: TranscriptionLanguage
    @Binding var candidates: [String]
    @Binding var hints: String

    var body: some View {
        Group {
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
        }
    }
}

struct RetranscriptionView: View {
    let meeting: MeetingHistoryItem
    @State var language: TranscriptionLanguage
    @State var candidates: [String]
    @State var hints: String
    let start: ([String], String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Re-transcribe meeting").font(.headline)
            Text(meeting.title).lineLimit(2)
            Text("Replaces the saved transcript, including edits, only after processing succeeds. The meeting name stays the same.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                TranscriptionOptionsView(language: $language, candidates: $candidates, hints: $hints)
            }
            .controlSize(.small)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Re-transcribe") {
                    dismiss()
                    start(language == .auto ? candidates : [language.rawValue], hints)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
