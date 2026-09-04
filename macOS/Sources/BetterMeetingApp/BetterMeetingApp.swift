import SwiftUI

@main
struct BetterMeetingApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 680, minHeight: 500)
        }
        .defaultSize(width: 760, height: 560)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
