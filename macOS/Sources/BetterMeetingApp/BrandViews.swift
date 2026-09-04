import AppKit
import SwiftUI

enum BrandAssets {
    static let applicationIcon: NSImage = loadImage(named: "AppIconMaster")
        ?? NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: nil)!

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

    private static func loadImage(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

struct ApplicationIcon: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: BrandAssets.applicationIcon)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct CaptureMark: View {
    let state: AppState
    let size: CGFloat

    private var isRecording: Bool { state == .recording }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color.brandGraphite)

            HStack(alignment: .center, spacing: size * 0.07) {
                bar(height: size * 0.24)
                bar(height: size * 0.44)
                bar(height: size * 0.29)
            }

            if isRecording {
                Circle()
                    .fill(Color.signalCoral)
                    .frame(width: size * 0.15, height: size * 0.15)
                    .offset(x: size * 0.33, y: size * 0.33)
                    .symbolEffect(.pulse, options: .repeating)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func bar(height: CGFloat) -> some View {
        Capsule()
            .fill(Color.warmPaper)
            .frame(width: size * 0.10, height: height)
    }
}

struct StatePill: View {
    let state: AppState

    var body: some View {
        Label(state.label, systemImage: state.symbol)
            .font(.callout.weight(.medium))
            .foregroundStyle(state == .idle ? Color.primary : state.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 1)
            }
    }
}

extension Color {
    static let brandGraphite = Color(red: 0.075, green: 0.105, blue: 0.135)
    static let warmPaper = Color(red: 0.97, green: 0.95, blue: 0.89)
    static let signalCoral = Color(red: 0.96, green: 0.25, blue: 0.22)
}

extension AppState {
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
        case .recording: .signalCoral
        case .complete: .green
        case .failed: .orange
        default: .secondary
        }
    }
}
