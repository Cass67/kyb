import SwiftUI

@main
struct KyBApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("KyB", systemImage: "keyboard") {
            RootView()
                .environmentObject(appState)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.window)
    }
}
