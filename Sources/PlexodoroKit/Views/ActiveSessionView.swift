import SwiftUI

struct ActiveSessionView: View {
    @ObservedObject var appState: AppState
    let serverURL: String
    let token: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                AlbumArt(url: currentThumbURL)
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(appState.formattedTime)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                    .contentTransition(.numericText())
            }
            .padding(.vertical, 4)

            if !appState.currentTrackTitle.isEmpty {
                Text(appState.currentTrackTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            if !appState.playlistTracks.isEmpty {
                HStack(spacing: 6) {
                    ProgressView(value: appState.player.currentProgress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                    Text(currentTrackTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .frame(height: 16)

                Divider()
                PlaylistView(
                    tracks: appState.playlistTracks,
                    currentTrackIndex: appState.currentTrackIndex,
                    isDownloading: appState.isDownloading
                )
            }

            HStack(spacing: 12) {
                Button {
                    appState.togglePlayback()
                } label: {
                    Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.playlistTracks.isEmpty)

                Button("Stop") {
                    appState.stopPomodoro()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }

            if appState.state == .finished {
                Text("Pomodoro complete!")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    private var currentThumbURL: URL? {
        let i = appState.currentTrackIndex
        guard i < appState.playlistTracks.count,
              let thumb = appState.playlistTracks[i].thumb else { return nil }
        return URL(string: "\(serverURL)\(thumb)?X-Plex-Token=\(token)")
    }

    private var currentTrackTime: String {
        let i = appState.currentTrackIndex
        guard i < appState.playlistTracks.count else { return "0:00" }
        let totalSec = appState.playlistTracks[i].duration / 1000
        let elapsedSec = Double(totalSec) * appState.player.currentProgress
        let remainingSec = max(0, Int(totalSec) - Int(elapsedSec))
        return String(format: "%d:%02d", remainingSec / 60, remainingSec % 60)
    }
}
