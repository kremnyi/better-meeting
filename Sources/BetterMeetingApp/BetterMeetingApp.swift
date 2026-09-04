import SwiftUI

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
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.terminationReply() ?? .terminateNow
    }
}
