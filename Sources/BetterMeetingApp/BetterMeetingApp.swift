import SwiftUI
import UserNotifications

@main
struct BetterMeetingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var processingFrame = 0
    @State private var iconTimer: Timer?
    @StateObject private var model: AppModel = {
        let model = AppModel()
        model.prepareSpeechModel()
        return model
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarControlView()
                .environmentObject(model)
                .onAppear { appDelegate.model = model }
        } label: {
            MenuBarStatusIcon(state: model.state, processingFrame: processingFrame)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: model.checkUpdatesOnLaunch, initial: true) { _, enabled in
            if enabled {
                Task { await model.checkForUpdates(automatically: true) }
            }
        }
        .onChange(of: model.state == .processing && !reduceMotion, initial: true) { _, animate in
            iconTimer?.invalidate()
            iconTimer = nil
            processingFrame = 0
            if animate {
                let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
                    processingFrame = (processingFrame + 1) % BrandAssets.processingMenuBarFrames.count
                }
                RunLoop.main.add(timer, forMode: .common)
                iconTimer = timer
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var model: AppModel?

    func applicationWillFinishLaunching(_ notification: Notification) {
        MeetingNotifications.center?.delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let folder = MeetingNotifications.folder(from: response.notification.request.content) else { return }
        NSWorkspace.shared.open(folder)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.terminationReply() ?? .terminateNow
    }
}
