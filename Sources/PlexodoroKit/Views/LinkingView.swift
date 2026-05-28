import SwiftUI

struct LinkingView: View {
    let code: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Link Your Plex Account")
                .font(.headline)

            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text("Go to")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Link("plex.tv/link", destination: URL(string: "https://plex.tv/link")!)
                        .font(.caption)
                    Text("on any device")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("and enter this code:")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(code)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .kerning(8)
            .padding(.vertical, 8)

            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Waiting for authorization…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Cancel", role: .cancel) {
                onCancel()
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(.vertical, 8)
    }
}
