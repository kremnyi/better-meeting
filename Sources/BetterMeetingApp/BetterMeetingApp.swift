import SwiftUI

@main
struct BetterMeetingApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarControlView()
                .environmentObject(model)
        } label: {
            MenuBarStatusIcon(state: model.state)
        }
        .menuBarExtraStyle(.window)
    }
}
