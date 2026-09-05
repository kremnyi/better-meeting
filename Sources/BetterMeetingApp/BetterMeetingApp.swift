import SwiftUI
import UserNotifications

@main
struct BetterMeetingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarControlView()
                .environmentObject(model)
                .onAppear { appDelegate.model = model }
        } label: {
            MenuBarStatusIcon(state: model.state)
        }
        .menuBarExtraStyle(.window)
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
