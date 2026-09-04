import AppKit
import SwiftUI

struct MenuBarControlView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                ApplicationIcon(size: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Better Meeting")
                        .font(.headline)
                    Text(model.state.label)
                        .font(.caption)
                        .foregroundStyle(model.state.tint)
                }

                Spacer()
            }

            Divider()

            HStack(spacing: 14) {
                CaptureMark(state: model.state, size: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.elapsedText)
                        .font(.title2.monospacedDigit())
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if model.state == .complete {
                HStack {
                    Button("Open folder") {
                        model.openCompletedFolder()
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
                .tint(model.state == .recording ? .signalCoral : .accentColor)
                .disabled(!model.canPerformPrimaryAction)
            }

            Divider()

            HStack {
                Button("Show Better Meeting") {
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
        .padding(18)
        .frame(width: 330)
    }
}
