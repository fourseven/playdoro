import SwiftUI

struct LinkingView: View {
    let code: String
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Theme.connectBackdrop.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Link Your Plex Account")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Go to")
                            .foregroundStyle(.white.opacity(0.55))
                        Link("plex.tv/link", destination: URL(string: "https://plex.tv/link")!)
                        Text("on any device")
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .font(.subheadline)
                    Text("and enter this code:")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }

                Text(code)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .kerning(8)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for authorization…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }

                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.vertical, 16)
        }
    }
}
