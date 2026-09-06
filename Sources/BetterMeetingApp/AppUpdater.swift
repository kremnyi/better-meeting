import Combine
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    enum Status: Equatable {
        case unchecked, checking, current, available(String), failed

        var availableVersion: String? {
            if case .available(let version) = self { version } else { nil }
        }

        var message: String {
            switch self {
            case .unchecked: ""
            case .checking: "Checking…"
            case .current: "Up to date"
            case .available: "Update available"
            case .failed: "Check failed"
            }
        }
    }

    static let releaseURL = URL(string: "https://github.com/kremnyi/better-meeting/releases/latest")!
    @Published var status: Status = .unchecked
    @Published var canCheckForUpdates = false
    @Published private(set) var installationWaiting = false
    private let isBusy: () -> Bool
    private var pendingInstallation: (() -> Void)?
    private var started = false
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
    )

    init(isBusy: @escaping () -> Bool) {
        self.isBusy = isBusy
        super.init()
    }

    func start(automaticChecks: Bool) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        controller.updater.automaticallyChecksForUpdates = automaticChecks
        guard !started else { return }
        started = true
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates, !isBusy() else { return }
        status = .checking
        controller.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool { false }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        status = .available(update.displayVersionString)
    }

    func standardUserDriverWillFinishUpdateSession() {
        if case .available = status { status = .unchecked }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        status = .current
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        if (error as NSError).code == SUError.noUpdateError.rawValue {
            status = .current
        } else if (error as NSError).code == SUError.installationCanceledError.rawValue {
            status = .unchecked
        } else if status == .checking {
            status = .failed
        }
        pendingInstallation = nil
        installationWaiting = false
    }

    func updater(
        _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        guard isBusy() else { return false }
        pendingInstallation = installHandler
        installationWaiting = true
        return true
    }

    func resumePendingInstallation() {
        guard !isBusy() else { return }
        let install = pendingInstallation
        pendingInstallation = nil
        installationWaiting = false
        install?()
    }
}
