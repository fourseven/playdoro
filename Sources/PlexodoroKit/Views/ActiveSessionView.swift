import SwiftUI

struct ActiveSessionView: View {
    @ObservedObject var appState: AppState
    let serverURL: String
    let token: String

    var body: some View {
        ZStack {
            AlbumArtBackdrop(url: currentThumbURL)

            VStack(spacing: 0) {
                scrollContent
                    .padding(.horizontal, 20)
                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                albumHero

                timerBlock

                trackInfo

                transportRow

                volumeRow

                if appState.state == .finished {
                    Text("Pomodoro complete")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .transition(.opacity)
                }

                if !appState.playlistTracks.isEmpty {
                    PlaylistView(
                        tracks: appState.playlistTracks,
                        currentTrackIndex: appState.currentTrackIndex,
                        isDownloading: appState.isDownloading,
                        serverURL: serverURL,
                        token: token,
                        isSeed: { track in appState.seedTracks.contains(where: { $0.id == track.id }) }
                    )
                    .padding(.top, 8)
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var albumHero: some View {
        AlbumArt(url: currentThumbURL)
            .frame(width: 240, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
    }

    private var timerBlock: some View {
        VStack(spacing: 4) {
            Text(appState.formattedTime)
                .font(Theme.timerFont)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .shadow(color: .black.opacity(0.4), radius: 12)

            Text(timeLabel)
                .font(.caption.weight(.medium))
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var trackInfo: some View {
        Group {
            if !appState.currentTrackTitle.isEmpty {
                VStack(spacing: 2) {
                    Text(appState.currentTrackTitle)
                        .font(Theme.trackTitleFont)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let subtitle = currentTrackSubtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var transportRow: some View {
        VStack(spacing: 8) {
            ProgressView(value: appState.player.currentProgress)
                .progressViewStyle(.linear)
                .tint(.white)

            HStack {
                Text(currentTrackElapsed)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(currentTrackRemaining)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 4)
    }

    private var volumeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            Slider(value: $appState.player.volume, in: 0...1)
                .tint(.white.opacity(0.85))
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 24) {
            Button {
                appState.stopPomodoro()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .foregroundStyle(.white.opacity(0.85))
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                appState.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 76, height: 76)
                        .shadow(color: Theme.accent.opacity(0.45), radius: 18, x: 0, y: 6)
                    Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .offset(x: appState.isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(appState.playlistTracks.isEmpty)
        }
    }

    private var timeLabel: String {
        if appState.state == .finished { return "complete" }
        return appState.isPlaying ? "in progress" : "paused"
    }

    private var currentTrackSubtitle: String? {
        let i = appState.currentTrackIndex
        guard i < appState.playlistTracks.count else { return nil }
        let track = appState.playlistTracks[i]
        return "\(track.artist) — \(track.album)"
    }

    private var currentThumbURL: URL? {
        let i = appState.currentTrackIndex
        guard i < appState.playlistTracks.count,
              let thumb = appState.playlistTracks[i].thumb else { return nil }
        return URL(string: "\(serverURL)\(thumb)?X-Plex-Token=\(token)")
    }

    private var currentTrackDurationSeconds: TimeInterval {
        let i = appState.currentTrackIndex
        guard i < appState.playlistTracks.count else { return 0 }
        return appState.playlistTracks[i].duration / 1000
    }

    private var currentTrackElapsed: String {
        let duration = currentTrackDurationSeconds
        guard duration > 0 else { return "0:00" }
        return format(seconds: duration * appState.player.currentProgress)
    }

    private var currentTrackRemaining: String {
        let duration = currentTrackDurationSeconds
        guard duration > 0 else { return "0:00" }
        let remaining = max(0, duration - duration * appState.player.currentProgress)
        return "-" + format(seconds: remaining)
    }

    private func format(seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
