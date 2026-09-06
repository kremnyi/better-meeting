import AppKit
import Sparkle
import XCTest
@testable import BetterMeetingApp

final class AppUpdaterTests: XCTestCase {
    @MainActor
    func testPreservesUpdateOptIn() throws {
        let suite = "BetterMeetingUpdates.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(AppModel(defaults: defaults).automaticUpdateChecks)
        defaults.set(true, forKey: "checkUpdatesOnLaunch")
        let model = AppModel(defaults: defaults)
        XCTAssertTrue(model.automaticUpdateChecks)
        model.automaticUpdateChecks = false
        XCTAssertFalse(AppModel(defaults: defaults).automaticUpdateChecks)
    }

    @MainActor
    func testInstallationWaitsForWorkAndResumesOnlyOnce() {
        _ = NSApplication.shared
        var busy = true
        let updates = AppUpdater(isBusy: { busy })
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: updates, userDriverDelegate: updates
        )
        let item = SUAppcastItem.empty()
        var installations = 0
        XCTAssertTrue(updates.updater(controller.updater, shouldPostponeRelaunchForUpdate: item) {
            installations += 1
        })
        XCTAssertTrue(updates.installationWaiting)
        updates.resumePendingInstallation()
        XCTAssertEqual(installations, 0)
        busy = false
        updates.resumePendingInstallation()
        updates.resumePendingInstallation()
        XCTAssertEqual(installations, 1)
        XCTAssertFalse(updates.installationWaiting)
        XCTAssertFalse(updates.updater(controller.updater, shouldPostponeRelaunchForUpdate: item) {
            XCTFail("Sparkle handles an idle installation directly")
        })
        busy = true
        XCTAssertTrue(updates.updater(controller.updater, shouldPostponeRelaunchForUpdate: item) {
            XCTFail("An aborted update must not resume")
        })
        updates.updater(controller.updater, didAbortWithError: URLError(.cancelled))
        busy = false
        updates.resumePendingInstallation()
        XCTAssertFalse(updates.installationWaiting)
    }
}
