import SwiftUI

@main
struct BetterMeetingApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Better Meeting", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(width: 760, height: 470)
        }
        .defaultSize(width: 760, height: 470)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarControlView()
                .environmentObject(model)
        } label: {
            Image(nsImage: BrandAssets.menuBarIcon)
                .accessibilityLabel("Better Meeting")
        }
        .menuBarExtraStyle(.window)
    }
}
