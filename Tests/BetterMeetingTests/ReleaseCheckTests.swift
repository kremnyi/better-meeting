import Foundation
import XCTest
@testable import BetterMeetingApp

final class ReleaseCheckTests: XCTestCase {
    @MainActor
    func testLaunchChecksPersistOptInShareResultsAndFailQuietly() async throws {
        let suite = "BetterMeetingUpdateCheck.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(FileManager.default.temporaryDirectory.appendingPathComponent(suite), forKey: "outputFolder")
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        XCTAssertFalse(model.checkUpdatesOnLaunch)
        await model.checkForUpdates(automatically: true, installedVersion: "0.3.10") { _ in
            XCTFail("Launch checks must not contact GitHub without opting in")
            return .current
        }
        XCTAssertEqual(model.releaseStatus, .unchecked)

        model.checkUpdatesOnLaunch = true
        XCTAssertTrue(AppModel(defaults: defaults).checkUpdatesOnLaunch)
        await model.checkForUpdates(automatically: true, installedVersion: "0.3.10") { version in
            XCTAssertEqual(version, "0.3.10")
            XCTAssertEqual(model.releaseStatus, .checking)
            await model.checkForUpdates(installedVersion: version) { _ in
                XCTFail("Manual checks must reuse an in-flight launch check")
                return .current
            }
            return .available("0.3.11")
        }
        XCTAssertEqual(model.releaseStatus.availableVersion, "0.3.11")
        await model.checkForUpdates(automatically: true, installedVersion: "0.3.10") { _ in
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(model.releaseStatus, .available("0.3.11"), "A failed launch check must preserve a known update")

        model.releaseStatus = .unchecked
        await model.checkForUpdates(automatically: true, installedVersion: "0.3.10") { _ in
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(model.releaseStatus, .unchecked, "Automatic failures must not show an error notice")
        await model.checkForUpdates(automatically: true, installedVersion: "0.3.10") { _ in
            model.checkUpdatesOnLaunch = false
            return .available("0.3.11")
        }
        XCTAssertEqual(model.releaseStatus, .unchecked, "Turning off checks must discard a pending automatic result")
        XCTAssertFalse(AppModel(defaults: defaults).checkUpdatesOnLaunch)
        await model.checkForUpdates(installedVersion: "0.3.10") { _ in throw URLError(.timedOut) }
        XCTAssertEqual(model.releaseStatus, .failed, "Manual checks must still explain failures when launch checks are off")
        XCTAssertEqual(model.state, .idle, "Update checks must not block recording")
    }

    func testStableReleasesVersionsAndInvalidResponses() throws {
        func response(_ tag: String, draft: Bool = false, prerelease: Bool = false) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": draft, "prerelease": prerelease])
        }
        for state: ReleaseCheck.Status in [.unchecked, .checking, .current, .failed] {
            XCTAssertNil(state.availableVersion, "Only a confirmed newer release may offer an update")
        }
        XCTAssertEqual(ReleaseCheck.Status.available("0.10.0").availableVersion, "0.10.0")
        let latest = try response("v0.10.0")
        XCTAssertEqual(try ReleaseCheck.status(from: latest, statusCode: 200, installedVersion: "0.9.0"), .available("0.10.0"))
        XCTAssertEqual(try ReleaseCheck.status(from: latest, statusCode: 200, installedVersion: "0.10.0"), .current)
        XCTAssertEqual(try ReleaseCheck.status(from: latest, statusCode: 200, installedVersion: "1.0.0"), .current)
        for invalid in [try response("v1.0.0-beta"), try response("v1.0.0\n"), try response("../latest"),
                        try response("v1.0.0", draft: true), try response("v1.0.0", prerelease: true),
                        Data("{\"message\":\"API rate limit exceeded\"}".utf8)] {
            XCTAssertThrowsError(try ReleaseCheck.status(from: invalid, statusCode: 200, installedVersion: "0.9.0"))
        }
        for status in [nil, 403, 404, 500] as [Int?] {
            XCTAssertThrowsError(try ReleaseCheck.status(from: latest, statusCode: status, installedVersion: "0.9.0"))
        }
        XCTAssertThrowsError(try ReleaseCheck.status(from: latest, statusCode: 200, installedVersion: "Development"))
    }

    func testHomebrewOnlyMatchesTheManagedApp() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? files.removeItem(at: root) }
        let app = root.appendingPathComponent("Installed/Better Meeting.app", isDirectory: true)
        let caskroom = root.appendingPathComponent("Caskroom")
        let version = caskroom.appendingPathComponent("0.3.6")
        try files.createDirectory(at: app, withIntermediateDirectories: true)
        try files.createDirectory(at: version, withIntermediateDirectories: true)
        let link = version.appendingPathComponent("Better Meeting.app")
        try files.createSymbolicLink(at: link, withDestinationURL: app)
        XCTAssertTrue(HomebrewUpdate.manages(appURL: app, caskroomURL: caskroom))
        XCTAssertFalse(HomebrewUpdate.manages(appURL: root.appendingPathComponent("ZIP/Better Meeting.app"), caskroomURL: caskroom))
        try files.removeItem(at: link)
        try files.createDirectory(at: link, withIntermediateDirectories: false)
        XCTAssertFalse(HomebrewUpdate.manages(appURL: app, caskroomURL: caskroom))
    }

    func testHomebrewScriptWaitsQuotesPathsAndStopsOnFailure() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("Meeting's update \(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: root) }
        func executable(_ url: URL, _ content: String) throws {
            try content.write(to: url, atomically: true, encoding: .utf8)
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        let brew = root.appendingPathComponent("brew")
        let open = root.appendingPathComponent("open")
        try executable(brew, """
        #!/bin/zsh
        if /bin/kill -0 "$BETTER_MEETING_TEST_PID" 2>/dev/null; then exit 42; fi
        print -r -- "brew $*" >> "$BETTER_MEETING_TEST_LOG"
        if [[ "$1" == "$BETTER_MEETING_FAIL_STEP" ]]; then exit 1; fi
        """)
        try executable(open, """
        #!/bin/zsh
        print -r -- "open $1" >> "$BETTER_MEETING_TEST_LOG"
        """)
        let app = root.appendingPathComponent("Meeting's $(echo unsafe).app")
        for (index, failure) in ["", "update", "upgrade"].enumerated() {
            let folder = root.appendingPathComponent("run-\(index)")
            try files.createDirectory(at: folder, withIntermediateDirectories: false)
            let log = root.appendingPathComponent("log-\(index)")
            let appProcess = Process()
            appProcess.executableURL = URL(fileURLWithPath: "/bin/sleep")
            appProcess.arguments = ["0.25"]
            try appProcess.run()
            let command = folder.appendingPathComponent("Update.command")
            try executable(command, HomebrewUpdate.script(
                appURL: app, processID: appProcess.processIdentifier, brewURL: brew, openURL: open
            ))
            let runner = Process()
            runner.executableURL = URL(fileURLWithPath: "/bin/zsh")
            runner.arguments = [command.path]
            runner.environment = [
                "BETTER_MEETING_TEST_PID": String(appProcess.processIdentifier),
                "BETTER_MEETING_TEST_LOG": log.path, "BETTER_MEETING_FAIL_STEP": failure
            ]
            let output = Pipe()
            runner.standardOutput = output
            runner.standardError = output
            try runner.run()
            appProcess.waitUntilExit()
            runner.waitUntilExit()
            let diagnostic = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(runner.terminationStatus, failure.isEmpty ? 0 : 1, diagnostic)
            var expected = "brew update\n"
            if failure != "update" { expected += "brew upgrade --cask --require-sha kremnyi/better-meeting/better-meeting\n" }
            if failure.isEmpty { expected += "open \(app.path)\n" }
            XCTAssertEqual(try String(contentsOf: log, encoding: .utf8), expected)
            XCTAssertFalse(files.fileExists(atPath: folder.path), "The temporary command must clean up after success or failure")
        }
    }
}
