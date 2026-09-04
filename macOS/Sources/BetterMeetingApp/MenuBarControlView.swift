import AppKit
import SwiftUI

struct MenuBarControlView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                if model.state == .idle || model.state == .failed {
                    meetingDetails
                    Divider()
                        .padding(.vertical, 8)
                }

                recordingStage

                if let error = model.errorMessage {
                    errorView(error)
                        .padding(.top, 12)
                }

                primaryControl
                    .padding(.top, 12)

                captureSummary
                    .padding(.top, 12)

                privacyNote
                    .padding(.top, 8)
            }
            .padding(16)

            Divider()

            HStack(spacing: 12) {
                Text("Better Meeting stays active when this panel is closed.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Better Meeting")
                    .font(.headline)

                Text(model.state == .recording ? "Recording in progress" : "Local meeting recorder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(model.state.label, systemImage: model.state.symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(model.state.tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var meetingDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Meeting title")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField("e.g. Product sync", text: $model.meetingTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Save to")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Choose…") {
                        model.chooseOutputFolder()
                    }
                }

                Label {
                    Text(model.outputRoot.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "folder")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var recordingStage: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.elapsedText)
                .font(.system(size: 34, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(model.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var primaryControl: some View {
        if model.state == .preparing {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text(model.primaryButtonTitle)
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 36)
        } else if model.state == .processing {
            VStack(alignment: .trailing, spacing: 5) {
                if let fraction = model.processingFraction {
                    ProgressView(value: fraction)

                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(.signalCoral)
            .accessibilityLabel(model.statusText)
            .frame(maxWidth: .infinity, minHeight: 36)
        } else if model.state == .complete {
            VStack(spacing: 10) {
                Button {
                    model.openCompletedTranscript()
                } label: {
                    Label("Open transcript", systemImage: "doc.plaintext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.brandGraphite)

                HStack {
                    Button("Show meeting folder") {
                        model.openCompletedFolder()
                    }

                    Spacer()

                    Button("New recording") {
                        model.reset()
                    }
                }
            }
        } else {
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
    }

    private var captureSummary: some View {
        Label(model.captureAccessText, systemImage: model.captureAccessSymbol)
            .font(.caption)
            .foregroundStyle(model.privacyPermission == nil ? Color.secondary : Color.orange)
    }

    private var privacyNote: some View {
        Label(
            "Recordings and transcripts stay on this Mac.",
            systemImage: "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(.tertiary)
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
                            model.openPrivacySettings()
                        }
                    }

                    if model.completedFolder != nil {
                        Button("Show saved files") {
                            model.openCompletedFolder()
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
