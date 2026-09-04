import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    recordingConsole

                    if let error = model.errorMessage {
                        errorView(error)
                    }

                    if model.state == .complete {
                        completedActions
                    }

                    privacyNote
                }
                .padding(24)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 13) {
            ApplicationIcon(size: 36)

            Text("Better Meeting")
                .font(.system(size: 21, weight: .semibold, design: .rounded))

            Spacer()

            StatePill(state: model.state)
        }
        .padding(.horizontal, 24)
        .padding(.top, 19)
        .padding(.bottom, 15)
    }

    private var recordingConsole: some View {
        VStack(spacing: 0) {
            meetingDetails

            Divider()
                .padding(.horizontal, 20)

            recordingStage

            Divider()
                .padding(.horizontal, 20)

            captureSummary
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    model.state == .recording
                        ? Color.signalCoral.opacity(0.7)
                        : Color(nsColor: .separatorColor).opacity(0.8),
                    lineWidth: model.state == .recording ? 1.5 : 1
                )
        }
    }

    private var meetingDetails: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow(alignment: .center) {
                Text("Meeting title")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)

                TextField("Product sync", text: $model.meetingTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .disabled(model.state.locksInputs)
            }

            GridRow(alignment: .center) {
                Text("Save to")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)

                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(.tertiary)

                    Text(model.outputRoot.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 12)

                    Button("Choose…") {
                        model.chooseOutputFolder()
                    }
                    .disabled(model.state.locksInputs)
                }
                .padding(.leading, 8)
            }
        }
        .padding(22)
    }

    private var recordingStage: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text(model.elapsedText)
                    .font(.system(size: 42, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(model.statusText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Button {
                model.primaryAction()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.78), lineWidth: 1.5)
                            .frame(width: 22, height: 22)

                        if model.state == .recording {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white)
                                .frame(width: 8, height: 8)
                        } else {
                            Circle()
                                .fill(.white)
                                .frame(width: 8, height: 8)
                        }
                    }

                    Text(model.primaryButtonTitle)
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 17)
                .frame(minWidth: 154, minHeight: 44)
                .background(Color.signalCoral, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!model.canPerformPrimaryAction)
            .opacity(model.canPerformPrimaryAction ? 1 : 0.46)
            .keyboardShortcut(.space, modifiers: [.command])
        }
        .padding(24)
    }

    private var captureSummary: some View {
        HStack {
            Label("Main display + system audio + microphone", systemImage: "rectangle.on.rectangle")

            Spacer()

            Text("⌘ Space")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 13)
    }

    private var privacyNote: some View {
        Label("Video and transcript stay on this Mac.", systemImage: "lock.shield")
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
    }

    private func errorView(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var completedActions: some View {
        HStack(spacing: 10) {
            Button("Open meeting folder") {
                model.openCompletedFolder()
            }
            .buttonStyle(.borderedProminent)

            Button("Record another meeting") {
                model.reset()
            }
        }
    }
}
