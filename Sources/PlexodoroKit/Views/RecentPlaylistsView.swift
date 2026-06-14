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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Recent")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: -8) {
                ForEach(playlist.seeds.prefix(3)) { track in
                    AlbumArt(url: thumbURL(for: track))
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(height: 26, alignment: .leading)

            Text(playlist.seeds.first?.title ?? "Untitled")
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)

            Text(playlist.seeds.count == 1
                 ? "1 seed"
                 : "\(playlist.seeds.count) seeds")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(6)
        .frame(width: 122)
        .background(Color(.systemFill))
        .cornerRadius(6)
    }
}
