import SwiftUI

struct ConnectView: View {
    let onConnect: () -> Void

    var body: some View {
        ZStack {
            Theme.connectBackdrop.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Theme.accentGradient.opacity(0.25))
                        .frame(width: 150, height: 150)
                        .blur(radius: 30)

                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 100, height: 100)
                        .shadow(color: Theme.accent.opacity(0.4), radius: 16)

                    Image(systemName: "timer")
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Text(AppIdentity.name)
                    .font(Theme.titleFont)
                    .foregroundStyle(.white)
                    .padding(.top, 24)

                Text("Focus sessions powered by\nyour Plex music library.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 36)
                    .padding(.top, 8)

                Spacer()

                Button {
                    onConnect()
                } label: {
                    Label("Connect to Plex", systemImage: "link")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }
}
