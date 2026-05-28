import SwiftUI
import Logging

public struct PlexodoroApp: App {
    @StateObject private var appState = AppState()
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    public init() {
        LoggingSystem.bootstrap { label in
            StreamLogHandler.standardOutput(label: label)
        }
    }

    public var body: some Scene {
        #if os(macOS)
        MenuBarExtra("Plexodoro", systemImage: "timer") {
            ContentView(appState: appState)
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            NavigationStack {
                ContentView(appState: appState)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background, appState.state == .running {
                    appState.pausePlayback()
                }
            }
        }
        #endif
    }
}
