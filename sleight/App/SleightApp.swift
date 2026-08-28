import SwiftUI

@main
struct SleightApp: App {
    var body: some Scene {
        WindowGroup("Sleight") {
            ContentView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowToolbarStyle(.unified)
    }
}