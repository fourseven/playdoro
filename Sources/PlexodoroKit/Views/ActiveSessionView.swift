import SwiftUI

struct ActiveSessionView: View {
    @ObservedObject var appState: AppState
    let serverURL: String
    let token: String

    var body: some View {
        VStack(spacing: 6) {
            if !appState.seedTracks.isEmpty {
                SeedChipsRow(seeds: appState.seedTracks, serverURL: serverURL, token: token)
            }

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
                    isDownloading: appState.isDownloading,
                    isSeed: { track in appState.seedTracks.contains(where: { $0.id == track.id }) }
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

struct SeedChipsRow: View {
    let seeds: [Track]
    let serverURL: String
    let token: String

    private func thumbURL(for track: Track) -> URL? {
        guard let thumb = track.thumb else { return nil }
        return URL(string: "\(serverURL)\(thumb)?X-Plex-Token=\(token)")
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "leaf.fill")
                .foregroundColor(.green)
                .font(.caption2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(seeds) { track in
                        HStack(spacing: 3) {
                            AlbumArt(url: thumbURL(for: track))
                                .frame(width: 14, height: 14)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                            Text(track.title)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(3)
                    }
                }
            }
        }
    }
}
