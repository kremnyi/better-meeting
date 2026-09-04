import AppKit
import SwiftUI

enum BrandAssets {
    static let menuBarIcon: NSImage = {
        let pointSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: pointSize)

        for filename in ["MenuBarIconTemplate.png", "MenuBarIconTemplate@2x.png"] {
            guard
                let url = Bundle.main.resourceURL?.appendingPathComponent(filename),
                let source = NSImage(contentsOf: url)
            else { continue }

            for representation in source.representations {
                representation.size = pointSize
                image.addRepresentation(representation)
            }
        }

        guard !image.representations.isEmpty else {
            return NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!
        }

        image.isTemplate = true
        return image
    }()
}

struct MenuBarStatusIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: AppState

    var body: some View {
        Group {
            if state == .processing {
                if reduceMotion {
                    Image(systemName: "hourglass")
                        .font(.system(size: 13, weight: .medium))
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                }
            } else {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: BrandAssets.menuBarIcon)

                    if state == .recording {
                        Circle()
                            .fill(Color.signalCoral)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: "Better Meeting"
        case .preparing: "Better Meeting, preparing to record"
        case .recording: "Better Meeting, recording"
        case .processing: "Better Meeting, processing recording"
        case .failed: "Better Meeting, needs attention"
        }
    }
}

extension Color {
    static let signalCoral = Color(red: 0.96, green: 0.25, blue: 0.22)
}

extension AppState {
    var label: String {
        switch self {
        case .idle: "Ready"
        case .preparing: "Preparing"
        case .recording: "Recording"
        case .processing: "Finishing"
        case .failed: "Needs attention"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "circle"
        case .preparing, .processing: "hourglass"
        case .recording: "record.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .recording: .signalCoral
        case .failed: .orange
        default: .secondary
        }
    }
}
