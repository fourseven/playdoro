import SwiftUI

struct ActiveSessionView: View {
    @ObservedObject var appState: AppState
    @Binding var showSettings: Bool

    @State private var palette: AlbumPalette?

    private var accentGradient: LinearGradient {
        if let palette {
            return LinearGradient(
                colors: [palette.primary, palette.secondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return Theme.accentGradient
    }

    private var accentColor: Color {
        palette?.primary ?? Theme.accent
    }

    var body: some View {
        ZStack {
            AlbumArtBackdrop(url: currentThumbURL) { newPalette in
                withAnimation(.easeInOut(duration: 0.6)) {
                    palette = newPalette
                }
            }

            content
        }
        #if os(iOS)
        .overlay(alignment: .topTrailing) { settingsButton }
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .animation(.easeInOut(duration: 0.4), value: palette)
    }

    #if os(iOS)
    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.top, 8)
    }
    #endif

    // iOS fills the screen (Spacers + docked up-next bar); macOS sizes a
    // compact menu-bar popover, so the layout hugs its content.
    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macContent
        #else
        VStack(spacing: 0) {
            sessionContent
                .padding(.horizontal, 20)
            upNextBar
        }
        #endif
    }

    #if os(macOS)
    private var macContent: some View {
        VStack(spacing: 14) {
            albumHero
            timerBlock

            if let warning = appState.sessionWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.yellow.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }

            trackInfo
            transportRow

            if appState.supportsVolume {
                volumeRow
            }

            if appState.state == .finished {
                Text("Pomodoro complete")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .transition(.opacity)
            }

            bottomBar
            upNextBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    #endif

    private var sessionContent: some View {
        VStack(spacing: 18) {
            albumHero

            timerBlock

            if let warning = appState.sessionWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.yellow.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }

            trackInfo

            transportRow

            if appState.state == .finished {
                Text("Pomodoro complete")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .transition(.opacity)
            }

            Spacer(minLength: 16)

            bottomBar

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 20)
    }

    @ViewBuilder
    private var upNextBar: some View {
        if !appState.playlistTracks.isEmpty {
            PlaylistView(
                tracks: appState.playlistTracks,
                currentTrackIndex: appState.currentTrackIndex,
                isDownloading: appState.isDownloading,
                thumbURL: { track in appState.catalog?.thumbURL(for: track) },
                isSeed: { track in appState.seedTracks.contains(where: { $0.id == track.id }) },
                accentColor: accentColor
            )
        }
    }

    private var albumHero: some View {
        AlbumArt(url: currentThumbURL)
            .aspectRatio(1, contentMode: .fit)
            // macOS VStack offers the ideal (nil) height, so a max-only frame
            // collapses the size-less resizable image to zero — pin it definite.
            #if os(macOS)
            .frame(width: 150, height: 150)
            #else
            .frame(maxWidth: 240, maxHeight: 240)
            #endif
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
                .shadow(color: accentColor.opacity(0.45), radius: 20)
                .shadow(color: .black.opacity(0.4), radius: 8)

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
            ProgressView(value: appState.currentProgress)
                .progressViewStyle(.linear)
                .tint(accentGradient)

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
            Slider(value: Binding(
                get: { appState.volume },
                set: { appState.setVolume($0) }
            ), in: 0...1)
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
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            Button {
                appState.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(accentGradient)
                        .frame(width: 76, height: 76)
                        .shadow(color: accentColor.opacity(0.55), radius: 22, x: 0, y: 6)
                    Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                        .offset(x: appState.isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(appState.playlistTracks.isEmpty)
        }
        .padding(.top, 4)
    }

    private var timeLabel: String {
        if appState.state == .finished { return "complete" }
        return appState.isPlaying ? "in progress" : "paused"
    }

    private var currentTrackSubtitle: String? {
        let i = appState.currentTrackIndex
        guard i < appState.playlistTracks.count else { return nil }
        return appState.playlistTracks[i].album
    }

    private var currentThumbURL: URL? {
        let i = appState.currentTrackIndex
        guard i < appState.playlistTracks.count else { return nil }
        return appState.catalog?.thumbURL(for: appState.playlistTracks[i])
    }

    private var currentTrackDurationSeconds: TimeInterval {
        let i = appState.currentTrackIndex
        guard i < appState.playlistTracks.count else { return 0 }
        return appState.playlistTracks[i].duration / 1000
    }

    private var currentTrackElapsed: String {
        let duration = currentTrackDurationSeconds
        guard duration > 0 else { return "0:00" }
        return format(seconds: duration * appState.currentProgress)
    }

    private var currentTrackRemaining: String {
        let duration = currentTrackDurationSeconds
        guard duration > 0 else { return "0:00" }
        let remaining = max(0, duration - duration * appState.currentProgress)
        return "-" + format(seconds: remaining)
    }

    private func format(seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
