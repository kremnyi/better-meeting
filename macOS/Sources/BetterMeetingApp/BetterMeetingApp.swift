import SwiftUI

@main
struct BetterMeetingApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Better Meeting", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 820, height: 620)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("Better Meeting", systemImage: "waveform") {
            MenuBarControlView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}
