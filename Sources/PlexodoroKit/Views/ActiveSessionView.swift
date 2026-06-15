import SwiftUI

struct ActiveSessionView: View {
    @ObservedObject var appState: AppState
    let serverURL: String
    let token: String

    var body: some View {
        VStack(spacing: 16) {
            AlbumArt(url: currentThumbURL)
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 2) {
                Text(appState.formattedTime)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .contentTransition(.numericText())
                    .foregroundColor(.primary)

                Text("remaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 4) {
                ProgressView(value: appState.player.currentProgress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)

                HStack {
                    Text(currentTrackElapsed)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text(currentTrackRemaining)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            if !appState.currentTrackTitle.isEmpty {
                Text(appState.currentTrackTitle)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 16) {
                Button {
                    appState.togglePlayback()
                } label: {
                    Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(appState.playlistTracks.isEmpty)

                Button {
                    appState.stopPomodoro()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.regular)
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(value: $appState.player.volume, in: 0...1)
                    .frame(maxWidth: 160)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if appState.state == .finished {
                Text("Pomodoro complete!")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if !appState.playlistTracks.isEmpty {
                Divider()

                PlaylistView(
                    tracks: appState.playlistTracks,
                    currentTrackIndex: appState.currentTrackIndex,
                    isDownloading: appState.isDownloading,
                    serverURL: serverURL,
                    token: token,
                    isSeed: { track in appState.seedTracks.contains(where: { $0.id == track.id }) }
                )
            }
        }
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
        let elapsed = duration * appState.player.currentProgress
        return format(seconds: elapsed)
    }

    private var currentTrackRemaining: String {
        let duration = currentTrackDurationSeconds
        guard duration > 0 else { return "0:00" }
        let elapsed = duration * appState.player.currentProgress
        return "-" + format(seconds: max(0, duration - elapsed))
    }

    private func format(seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
