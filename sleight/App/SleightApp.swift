import SwiftUI

@main
struct SleightApp: App {
    var body: some Scene {
        WindowGroup("Sleight") {
            ContentView()
                .frame(minWidth: 960, minHeight: 640)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: NSScreen.main?.frame.width ?? 1440,
                     height: NSScreen.main?.frame.height ?? 900)
        .windowResizability(.contentSize)
    }
}
