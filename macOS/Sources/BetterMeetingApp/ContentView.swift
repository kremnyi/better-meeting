import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 24) {
                meetingDetails
                recorder

                if let error = model.errorMessage {
                    errorView(error)
                }

                if model.completedFolder != nil {
                    completedActions
                }

                Spacer(minLength: 0)

                Label(
                    "Recording and transcription stay on this Mac.",
                    systemImage: "lock.shield"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Better Meeting")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))

                Text("Record your main display, meeting audio, and microphone.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(model.state.label, systemImage: model.state.symbol)
                .font(.callout.weight(.medium))
                .foregroundStyle(model.state.tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(model.state.tint.opacity(0.1), in: Capsule())
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 22)
    }

    private var meetingDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Meeting title", text: $model.meetingTitle)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .disabled(model.state.locksInputs)

            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)

                Text(model.outputRoot.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Choose…") {
                    model.chooseOutputFolder()
                }
                .disabled(model.state.locksInputs)
            }
        }
    }

    private var recorder: some View {
        VStack(spacing: 16) {
            Text(model.elapsedText)
                .font(.system(size: 54, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(model.statusText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                model.primaryAction()
            } label: {
                Label(model.primaryButtonTitle, systemImage: model.primaryButtonSymbol)
                    .frame(minWidth: 150)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(model.state == .recording ? .red : .accentColor)
            .disabled(!model.canPerformPrimaryAction)
            .keyboardShortcut(.space, modifiers: [.command])
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 24)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private func errorView(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var completedActions: some View {
        HStack {
            Button("Open meeting folder") {
                model.openCompletedFolder()
            }

            Button("Record another meeting") {
                model.reset()
            }
        }
    }
}

private extension AppState {
    var label: String {
        switch self {
        case .idle: "Ready"
        case .preparing: "Preparing"
        case .recording: "Recording"
        case .processing: "Processing"
        case .complete: "Complete"
        case .failed: "Needs attention"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "circle"
        case .preparing, .processing: "hourglass"
        case .recording: "record.circle.fill"
        case .complete: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .recording: .red
        case .complete: .green
        case .failed: .orange
        default: .secondary
        }
    }
}
