import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var model: AppModel
    var version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    var homebrewAvailable = HomebrewUpdate.isAvailable
    private var status: ReleaseCheck.Status { model.releaseStatus }
    @State private var updating = false
    @State private var updateError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Better Meeting").font(.headline)
                Text(version.map { "Version \($0)" } ?? "Development build")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(updateError ?? status.message)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)

                if let newerVersion = status.availableVersion {
                    if homebrewAvailable {
                        Button(updating ? "Opening Terminal…" : "Update to \(newerVersion)") {
                            Task { await updateWithHomebrew() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updating || model.state != .idle)
                        Text(model.state == .idle
                             ? "Uses Homebrew in Terminal. Quits this app and reopens it after updating."
                             : "Finish recording, transcription, or export before updating.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Link("Download \(newerVersion)", destination: ReleaseCheck.releaseURL)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button(status == .checking ? "Checking…" : status == .failed ? "Try Again" : "Check for Updates") {
                        Task { await checkForUpdates() }
                    }
                    .disabled(status == .checking || version == nil)
                }
            }

            Toggle("Check for updates on launch", isOn: $model.checkUpdatesOnLaunch)
                .toggleStyle(.checkbox)
                .help("Checks GitHub when Better Meeting opens. Updates are installed only when you choose.")

            Link("Release notes", destination: ReleaseCheck.releaseURL)
        }
        .font(.callout)
        .controlSize(.small)
        .padding(20)
        .frame(width: 304, alignment: .leading)
    }

    @MainActor
    private func checkForUpdates() async {
        updateError = nil
        await model.checkForUpdates(installedVersion: version)
    }

    @MainActor
    private func updateWithHomebrew() async {
        guard !updating, status.availableVersion != nil, model.state == .idle else { return }
        updating = true
        updateError = nil
        defer { updating = false }
        do {
            try await HomebrewUpdate.launch()
            if model.state == .idle {
                NSApp.terminate(nil)
            } else {
                updateError = "Terminal is waiting. Finish your meeting and quit to continue updating."
            }
        } catch {
            updateError = "Couldn't start the update. Try again or open the release notes."
        }
    }
}

enum ReleaseCheck {
    enum Status: Equatable {
        case unchecked, checking, current, available(String), failed

        var availableVersion: String? {
            if case .available(let version) = self { version } else { nil }
        }

        var message: String {
            switch self {
            case .unchecked: "Update checks contact GitHub."
            case .checking: "Checking GitHub for a newer release…"
            case .current: "You're up to date."
            case .available(let version): "Version \(version) is available."
            case .failed: "Couldn't check for updates. Try again or open the release notes."
            }
        }
    }

    static let releaseURL = URL(string: "https://github.com/kremnyi/better-meeting/releases/latest")!

    static func latest(installedVersion: String) async throws -> Status {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/kremnyi/better-meeting/releases/latest")!,
            cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        return try status(
            from: data, statusCode: (response as? HTTPURLResponse)?.statusCode,
            installedVersion: installedVersion
        )
    }

    static func status(from data: Data, statusCode: Int?, installedVersion: String) throws -> Status {
        struct Release: Decodable {
            let tag_name: String
            let draft: Bool
            let prerelease: Bool
        }

        guard statusCode == 200 else { throw URLError(.badServerResponse) }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease, release.tag_name.hasPrefix("v") else {
            throw URLError(.cannotParseResponse)
        }
        let version = String(release.tag_name.dropFirst())
        // ponytail: stable vX.Y.Z tags only; add semantic-version parsing if release channels are introduced.
        let pattern = #"\A[0-9]+\.[0-9]+\.[0-9]+\z"#
        guard version.range(of: pattern, options: .regularExpression) != nil,
              installedVersion.range(of: pattern, options: .regularExpression) != nil else {
            throw URLError(.cannotParseResponse)
        }
        return version.compare(installedVersion, options: .numeric) == .orderedDescending ? .available(version) : .current
    }
}
