import SwiftUI

struct RecentPlaylistsView: View {
    let playlists: [SeedPlaylist]
    let serverURL: String
    let token: String
    let onTap: (SeedPlaylist) -> Void

    private func thumbURL(for track: Track) -> URL? {
        guard let thumb = track.thumb else { return nil }
        return URL(string: "\(serverURL)\(thumb)?X-Plex-Token=\(token)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                Text("Recent")
                    .font(.caption.weight(.medium))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(playlists) { playlist in
                        Button {
                            onTap(playlist)
                        } label: {
                            card(for: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func card(for playlist: SeedPlaylist) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: -10) {
                ForEach(Array(playlist.seeds.prefix(3).enumerated()), id: \.element.id) { i, track in
                    AlbumArt(url: thumbURL(for: track))
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.background, lineWidth: 1.5)
                        )
                        .zIndex(Double(3 - i))
                }
            }
            .frame(height: 36, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.seeds.first?.title ?? "Untitled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(playlist.seeds.count == 1
                     ? "1 seed"
                     : "\(playlist.seeds.count) seeds")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(10)
        .frame(width: 148)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}
