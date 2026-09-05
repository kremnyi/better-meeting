import Foundation
import XCTest
@testable import BetterMeetingApp

final class ReleaseCheckTests: XCTestCase {
    func testStableReleasesVersionsAndInvalidResponses() throws {
        func response(_ tag: String, draft: Bool = false, prerelease: Bool = false) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": draft, "prerelease": prerelease])
        }
        let latest = try response("v0.10.0")
        XCTAssertEqual(try ReleaseCheck.newerVersion(from: latest, statusCode: 200, installedVersion: "0.9.0"), "0.10.0")
        XCTAssertNil(try ReleaseCheck.newerVersion(from: latest, statusCode: 200, installedVersion: "0.10.0"))
        XCTAssertNil(try ReleaseCheck.newerVersion(from: latest, statusCode: 200, installedVersion: "1.0.0"))
        for invalid in [try response("v1.0.0-beta"), try response("v1.0.0\n"), try response("../latest"),
                        try response("v1.0.0", draft: true), try response("v1.0.0", prerelease: true),
                        Data("{\"message\":\"API rate limit exceeded\"}".utf8)] {
            XCTAssertThrowsError(try ReleaseCheck.newerVersion(from: invalid, statusCode: 200, installedVersion: "0.9.0"))
        }
        for status in [nil, 403, 404, 500] as [Int?] {
            XCTAssertThrowsError(try ReleaseCheck.newerVersion(from: latest, statusCode: status, installedVersion: "0.9.0"))
        }
        XCTAssertThrowsError(try ReleaseCheck.newerVersion(from: latest, statusCode: 200, installedVersion: "Development"))
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
