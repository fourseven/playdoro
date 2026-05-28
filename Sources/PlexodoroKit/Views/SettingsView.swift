import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            if appState.isConfigured {
                VStack(spacing: 6) {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)

                    if !appState.serverName.isEmpty {
                        Text(appState.serverName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(appState.serverURL)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Divider()

                Button("Disconnect", role: .destructive) {
                    appState.disconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text("Connect to Plex from the main screen")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
