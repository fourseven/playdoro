import SwiftUI

struct DiscoveringView: View {
    var body: some View {
        ZStack {
            Theme.connectBackdrop.ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Theme.accentGradient.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .blur(radius: 26)

                    Circle()
                        .fill(Theme.accent.opacity(0.25))
                        .frame(width: 78, height: 78)

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }

                Text("Connecting to Plex")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    ProgressView()
                    Text("Finding your server…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }
}
