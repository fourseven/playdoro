import SwiftUI
import Logging

public struct PlexodoroApp: App {
    @StateObject private var appState = AppState()

    public init() {
        LoggingSystem.bootstrap { label in
            StreamLogHandler.standardOutput(label: label)
        }
    }

    public var body: some Scene {
        #if os(macOS)
        MenuBarExtra(AppIdentity.name, systemImage: "timer") {
            ContentView(appState: appState)
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            NavigationStack {
                ContentView(appState: appState)
            }
        }
        #endif
    }
}
