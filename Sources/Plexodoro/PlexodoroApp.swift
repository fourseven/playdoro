import SwiftUI

@main
struct PlexodoroApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Plexodoro", systemImage: appState.state == .running ? "timer" : "timer") {
            ContentView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
        }
    }
}

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            if !appState.isConfigured {
                VStack(spacing: 8) {
                    Text("Plexodoro")
                        .font(.headline)
                    Text("Configure your Plex server in Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if appState.state == .idle {
                idleView
            } else {
                activeView
            }

            Divider()

            Button("Settings…") {
                openSettings()
            }
            .buttonStyle(.plain)
            .font(.caption)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding()
        .frame(width: 240)
    }

    private func openSettings() {
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == "plexodoro-settings" }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentViewController: NSHostingController(rootView: SettingsView(appState: appState))
        )
        window.title = "Settings"
        window.identifier = NSUserInterfaceItemIdentifier("plexodoro-settings")
        window.setContentSize(NSSize(width: 400, height: 160))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.circle")
                .font(.largeTitle)

            Button("Start pomodoro from current track") {
                appState.startPomodoro()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var activeView: some View {
        VStack(spacing: 8) {
            Text(appState.formattedTime)
                .font(.system(.title, design: .monospaced))
                .contentTransition(.numericText())

            if !appState.currentTrackTitle.isEmpty {
                Text(appState.currentTrackTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Button("Stop") {
                appState.stopPomodoro()
            }
            .buttonStyle(.bordered)
            .tint(.red)

            if appState.state == .finished {
                Text("Pomodoro complete!")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            TextField("Plex Server URL", text: $appState.serverURL)
                .textFieldStyle(.roundedBorder)

            SecureField("Plex Token", text: $appState.token)
                .textFieldStyle(.roundedBorder)

            HStack {
                if appState.isConfigured {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if !appState.token.isEmpty {
                    Label("Not connected", systemImage: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                }

                Spacer()

                Button("Test Connection") {
                    appState.updateCredentials(
                        serverURL: appState.serverURL,
                        token: appState.token
                    )
                }
            }

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
