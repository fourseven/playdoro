import SwiftUI
import Logging

@main
struct PlexodoroApp: App {
    @StateObject private var appState = AppState()

    init() {
        LoggingSystem.bootstrap { label in
            StreamLogHandler.standardOutput(label: label)
        }
    }

    var body: some Scene {
        MenuBarExtra("Plexodoro", systemImage: "timer") {
            ContentView(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}
