import SwiftUI

struct PlaylistView: View {
    let tracks: [Track]
    let currentTrackIndex: Int
    let isDownloading: Bool
    let serverURL: String
    let token: String
    let isSeed: (Track) -> Bool

    init(
        tracks: [Track],
        currentTrackIndex: Int,
        isDownloading: Bool,
        serverURL: String,
        token: String,
        isSeed: @escaping (Track) -> Bool = { _ in false }
    ) {
        self.tracks = tracks
        self.currentTrackIndex = currentTrackIndex
        self.isDownloading = isDownloading
        self.serverURL = serverURL
        self.token = token
        self.isSeed = isSeed
    }

    private func thumbURL(for track: Track) -> URL? {
        guard let thumb = track.thumb else { return nil }
        return URL(string: "\(serverURL)\(thumb)?X-Plex-Token=\(token)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Up next")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(tracks.count) tracks")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                        HStack(spacing: 8) {
                            thumbnail(for: i, track: track)
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundColor(i == currentTrackIndex ? .primary : .secondary)

                                Text(track.artist)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if isSeed(track) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(i == currentTrackIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                        .cornerRadius(8)
                    }
                }
            }
            .frame(minHeight: 80, maxHeight: 180)
        }
    }

    @ViewBuilder
    private func thumbnail(for index: Int, track: Track) -> some View {
        ZStack {
            AlbumArt(url: thumbURL(for: track))

            if index == currentTrackIndex {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.35))

                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            } else if isDownloading && !track.isDownloaded {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.35))

                ProgressView()
                    .scaleEffect(0.6)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
    }
}
