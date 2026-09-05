import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var model: AppModel
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    private let homebrewAvailable = HomebrewUpdate.isAvailable
    @State private var checking = false
    @State private var updating = false
    @State private var result: String?

    var body: some View {
        VStack(spacing: 12) {
            Text("Better Meeting")
                .font(.headline)
            Text(version.map { "Version \($0)" } ?? "Development build")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Link("Release page", destination: ReleaseCheck.releaseURL)

            Button(checking ? "Checking…" : "Check for Updates") {
                Task { await checkForUpdates() }
            }
            .disabled(checking || version == nil)

            if homebrewAvailable {
                Button(updating ? "Opening Terminal…" : "Update with Homebrew") {
                    Task { await updateWithHomebrew() }
                }
                .disabled(updating || model.state != .idle)
                .help("Finish your recording or transcription before updating")
                Text("Opens Terminal and quits this app. Reopens after a successful update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let result {
                Text(result)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .frame(width: 280)
    }

    @MainActor
    private func checkForUpdates() async {
        guard !checking, let version else { return }
        checking = true
        result = nil
        defer { checking = false }

        do {
            var request = URLRequest(
                url: URL(string: "https://api.github.com/repos/kremnyi/better-meeting/releases/latest")!,
                cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15
            )
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            let newerVersion = try ReleaseCheck.newerVersion(
                from: data, statusCode: (response as? HTTPURLResponse)?.statusCode,
                installedVersion: version
            )
            result = newerVersion.map { "Version \($0) is available." }
                ?? "You're up to date."
        } catch {
            result = "Couldn't check for updates. Try again or open the release page."
        }
    }

    @MainActor
    private func updateWithHomebrew() async {
        guard !updating, model.state == .idle else { return }
        updating = true
        defer { updating = false }
        do {
            try await HomebrewUpdate.launch()
            if model.state == .idle {
                NSApp.terminate(nil)
            } else {
                result = "Terminal is waiting. Finish your meeting and quit to continue updating."
            }
        } catch {
            result = "Couldn't start the update. Try again or open the release page."
        }
    }
}

enum ReleaseCheck {
    static let releaseURL = URL(string: "https://github.com/kremnyi/better-meeting/releases/latest")!

    static func newerVersion(from data: Data, statusCode: Int?, installedVersion: String) throws -> String? {
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
        return version.compare(installedVersion, options: .numeric) == .orderedDescending ? version : nil
    }
}
