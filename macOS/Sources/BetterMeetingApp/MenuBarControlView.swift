import AppKit
import SwiftUI

struct MenuBarControlView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Better Meeting")
                    .font(.headline)

                Spacer()

                Label(model.state.label, systemImage: model.state.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(model.state.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.elapsedText)
                    .font(.system(size: 30, weight: .medium, design: .monospaced))
                    .monospacedDigit()

                Text(model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if model.state == .preparing || model.state == .processing {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.primaryButtonTitle)
                        .font(.callout.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 32)
            } else if model.state == .complete {
                HStack {
                    Button("Open transcript") {
                        model.openCompletedTranscript()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("New recording") {
                        model.reset()
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

            Divider()

            HStack {
                Button("Open Better Meeting") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 300)
    }
}
