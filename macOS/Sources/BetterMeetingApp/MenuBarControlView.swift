import AppKit
import SwiftUI

struct MenuBarControlView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            content
                .padding(14)

            Divider()

            HStack(spacing: 8) {
                Label("Files stay on this Mac", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Better Meeting")
                .font(.headline)

            Spacer()

            Label(model.state.label, systemImage: model.state.symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(model.state.tint)
        }
        .padding(.horizontal, 14)
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
        case .complete:
            completeContent
        case .failed:
            failedContent
        }
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Meeting name (optional)", text: $model.meetingTitle)
                .textFieldStyle(.roundedBorder)

            destinationButton

            primaryActionButton

            captureSummary
        }
    }

    private var destinationButton: some View {
        Button {
            model.chooseOutputFolder()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")

                Text(model.outputRoot.lastPathComponent)
                    .lineLimit(1)

                Spacer()

                Text("Change")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.outputRoot.path)
        .accessibilityLabel("Save recordings to \(model.outputRoot.path)")
        .accessibilityHint("Choose a different folder")
    }

    private var preparingContent: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)

            Text(model.statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
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

    private var completeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.elapsedText)
                    .font(.title3.monospacedDigit())

                Text("recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                Button("Show in Finder") {
                    model.openCompletedFolder()
                }

                Spacer()

                Button("New recording") {
                    model.reset()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var failedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = model.errorMessage {
                errorView(error)
            }

            primaryActionButton

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
