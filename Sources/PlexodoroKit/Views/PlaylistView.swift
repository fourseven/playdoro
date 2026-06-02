import SwiftUI

struct PlaylistView: View {
    let tracks: [Track]
    let currentTrackIndex: Int
    let isDownloading: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                    HStack(spacing: 4) {
                        if i == currentTrackIndex {
                            Image(systemName: "play.fill")
                                .font(.system(size: 7))
                                .foregroundColor(.green)
                                .frame(width: 12)
                        } else if isDownloading && !track.isDownloaded {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 11, height: 11)
                        } else {
                            Text("\(i + 1).")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 12, alignment: .trailing)
                        }
                        Text(track.title)
                            .font(.caption2)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(i == currentTrackIndex ? Color.green.opacity(0.1) : Color.clear)
                    .cornerRadius(2)
                }
            }
        }
        .frame(minHeight: 120, maxHeight: 200)
    }
}
