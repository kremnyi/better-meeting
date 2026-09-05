import AppKit

enum HomebrewUpdate {
    // ponytail: standard Apple Silicon Homebrew prefix; other installations use the release link.
    static let brewURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
    static let caskroomURL = URL(fileURLWithPath: "/opt/homebrew/Caskroom/better-meeting")

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: brewURL.path)
            && manages(appURL: Bundle.main.bundleURL, caskroomURL: caskroomURL)
    }

    static func manages(appURL: URL, caskroomURL: URL) -> Bool {
        let files = FileManager.default
        let versions = (try? files.contentsOfDirectory(
            at: caskroomURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        return versions.contains { version in
            let link = version.appendingPathComponent("Better Meeting.app")
            return (try? files.destinationOfSymbolicLink(atPath: link.path)) != nil
                && link.resolvingSymlinksInPath().path == appURL.resolvingSymlinksInPath().path
        }
    }

    @MainActor
    static func launch() async throws {
        guard isAvailable else { throw CocoaError(.fileNoSuchFile) }
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent("BetterMeeting-Update-\(UUID().uuidString)")
        try files.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let command = folder.appendingPathComponent("Update Better Meeting.command")
            try script(appURL: Bundle.main.bundleURL, processID: ProcessInfo.processInfo.processIdentifier)
                .write(to: command, atomically: true, encoding: .utf8)
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: command.path)
            _ = try await NSWorkspace.shared.open(
                [command], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        } catch {
            try? files.removeItem(at: folder)
            throw error
        }
    }

    static func script(
        appURL: URL, processID: Int32, brewURL: URL = HomebrewUpdate.brewURL,
        openURL: URL = URL(fileURLWithPath: "/usr/bin/open")
    ) -> String {
        func quote(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return """
        #!/bin/zsh
        set -e
        trap '/bin/rm -f -- "$0"; /bin/rmdir -- "${0:h}"' EXIT
        echo 'Waiting for Better Meeting to quit. Press Control-C to cancel.'
        while /bin/kill -0 \(processID) 2>/dev/null; do /bin/sleep 1; done
        if \(quote(brewURL.path)) update && \
            HOMEBREW_NO_AUTO_UPDATE=1 \(quote(brewURL.path)) upgrade --cask --require-sha kremnyi/better-meeting/better-meeting; then
            \(quote(openURL.path)) \(quote(appURL.path))
        else
            echo 'Update failed. Review the Homebrew error above before reopening Better Meeting.' >&2
            exit 1
        fi
        """
    }
}
