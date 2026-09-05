import AppKit
import SwiftUI

enum BrandAssets {
    static let menuBarIcon: NSImage = {
        guard let image = NSImage(named: "MenuBarIconTemplate") else {
            return NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    static func recordingMenuBarIcon(for colorScheme: ColorScheme) -> NSImage {
        let pointSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: pointSize, flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            menuBarIcon.draw(in: rect)
            (colorScheme == .dark ? NSColor.white : NSColor.black).setFill()
            rect.fill(using: .sourceIn)
            NSGraphicsContext.restoreGraphicsState()

            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: NSRect(x: 12, y: 12, width: 6, height: 6)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

struct MenuBarStatusIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let state: AppState

    @ViewBuilder
    var body: some View {
        if state == .processing {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .medium))
                .symbolEffect(
                    .rotate,
                    options: .repeating,
                    isActive: !reduceMotion
                )
                .statusIconAccessibility(accessibilityLabel)
        } else {
            Image(
                nsImage: state == .recording
                    ? BrandAssets.recordingMenuBarIcon(for: colorScheme)
                    : BrandAssets.menuBarIcon
            )
            .statusIconAccessibility(accessibilityLabel)
        }
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

private extension View {
    func statusIconAccessibility(_ label: String) -> some View {
        frame(width: 18, height: 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
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
