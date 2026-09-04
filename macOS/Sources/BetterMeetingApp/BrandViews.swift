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

extension Color {
    static let brandGraphite = Color(red: 0.075, green: 0.105, blue: 0.135)
    static let signalCoral = Color(red: 0.96, green: 0.25, blue: 0.22)
}

extension AppState {
    var label: String {
        switch self {
        case .idle: "Ready"
        case .preparing: "Preparing"
        case .recording: "Recording"
        case .processing: "Finishing"
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
        case .recording: .signalCoral
        case .complete: .green
        case .failed: .orange
        default: .secondary
        }
    }
}
