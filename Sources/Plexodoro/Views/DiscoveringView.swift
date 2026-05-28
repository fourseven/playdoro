import SwiftUI

struct DiscoveringView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 24))
                .foregroundColor(.accentColor)

            Text("Connecting to Plex")
                .font(.headline)

            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Finding your server…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}
