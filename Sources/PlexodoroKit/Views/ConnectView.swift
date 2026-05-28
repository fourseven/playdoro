import SwiftUI

struct ConnectView: View {
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 32))
                .foregroundColor(.accentColor)

            Text("Plexodoro")
                .font(.headline)

            Text("Pomodoro timer synced\nwith your Plex library.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                onConnect()
            } label: {
                Label("Connect to Plex", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.vertical, 8)
    }
}
