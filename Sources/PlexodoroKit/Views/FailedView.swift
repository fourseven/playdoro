import SwiftUI

struct FailedView: View {
    let message: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Theme.connectBackdrop.ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 110, height: 110)
                        .blur(radius: 22)

                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 74, height: 74)

                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.orange)
                }

                Text("Connection Failed")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    Button {
                        onRetry()
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 32)
            }
            .padding(.vertical, 16)
        }
    }
}
