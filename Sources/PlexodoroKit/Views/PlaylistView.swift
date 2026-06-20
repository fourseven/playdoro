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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .font(.caption2)
                Text("Up next")
                    .font(.caption.weight(.medium))
                    .textCase(.uppercase)
                    .tracking(1)
                Spacer()
                Text("\(tracks.count) tracks")
                    .font(.caption2.monospacedDigit())
            }
            .foregroundStyle(.white.opacity(0.55))

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                        HStack(spacing: 12) {
                            thumbnail(for: i, track: track)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.subheadline.weight(i == currentTrackIndex ? .semibold : .regular))
                                    .lineLimit(1)
                                    .foregroundStyle(i == currentTrackIndex ? .white : .white.opacity(0.75))

                                Text(track.artist)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .foregroundStyle(.white.opacity(0.5))
                            }

                            Spacer()

                            if isSeed(track) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            i == currentTrackIndex
                                ? Theme.accent.opacity(0.18)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                }
            }
            .frame(minHeight: 80, maxHeight: 200)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func thumbnail(for index: Int, track: Track) -> some View {
        ZStack {
            AlbumArt(url: thumbURL(for: track))

            if index == currentTrackIndex {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.35))

                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } else if isDownloading && !track.isDownloaded {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.35))

                ProgressView()
                    .scaleEffect(0.6)
                    .tint(.white)
            }
        }
    }
}
