import SwiftUI

struct PlaylistView: View {
    let tracks: [Track]
    let currentTrackIndex: Int
    let isDownloading: Bool
    let thumbURL: (Track) -> URL?
    let isSeed: (Track) -> Bool
    var accentColor: Color = Theme.accent

    @State private var showQueue = false

    init(
        tracks: [Track],
        currentTrackIndex: Int,
        isDownloading: Bool,
        thumbURL: @escaping (Track) -> URL?,
        isSeed: @escaping (Track) -> Bool = { _ in false },
        accentColor: Color = Theme.accent
    ) {
        self.tracks = tracks
        self.currentTrackIndex = currentTrackIndex
        self.isDownloading = isDownloading
        self.thumbURL = thumbURL
        self.isSeed = isSeed
        self.accentColor = accentColor
    }

    private var upcoming: [(index: Int, track: Track)] {
        tracks.enumerated()
            .filter { $0.offset > currentTrackIndex }
            .map { (index: $0.offset, track: $0.element) }
    }

    var body: some View {
        Button {
            showQueue = true
        } label: {
            peek
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .sheet(isPresented: $showQueue) {
            queueSheet
        }
        #else
        .popover(isPresented: $showQueue, arrowEdge: .top) {
            queueSheet
                .frame(width: 320, height: 420)
                .background(Theme.background)
        }
        #endif
    }

    private var peek: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.55))

            VStack(alignment: .leading, spacing: 2) {
                Text("Up next · \(tracks.count) tracks")
                    .font(.caption2.weight(.medium))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.55))
                Text(upcoming.first?.track.title ?? "End of queue")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                if let artist = upcoming.first?.track.artist {
                    Text(artist)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            Image(systemName: "chevron.up")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { peekBackground }
        .overlay(alignment: .top) { peekBorder }
    }

    // iOS: a full-width dock flush to the bottom safe area. macOS sits in a
    // popover with no safe area, so it's a self-contained rounded pill.
    #if os(iOS)
    @ViewBuilder
    private var peekBackground: some View {
        dockShape
            .fill(.ultraThinMaterial)
            .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var peekBorder: some View {
        dockShape
            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            .ignoresSafeArea(edges: .bottom)
    }

    private var dockShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
    }
    #else
    private var pillShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    @ViewBuilder
    private var peekBackground: some View {
        pillShape.fill(.ultraThinMaterial)
    }

    @ViewBuilder
    private var peekBorder: some View {
        pillShape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
    }
    #endif

    private var queueSheet: some View {
        QueueSheet(
            tracks: tracks,
            currentTrackIndex: currentTrackIndex,
            isDownloading: isDownloading,
            thumbURL: thumbURL,
            isSeed: isSeed,
            accentColor: accentColor
        )
    }
}

private struct QueueSheet: View {
    let tracks: [Track]
    let currentTrackIndex: Int
    let isDownloading: Bool
    let thumbURL: (Track) -> URL?
    let isSeed: (Track) -> Bool
    let accentColor: Color

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(tracks.count) tracks")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                        QueueRow(
                            track: track,
                            thumbURL: thumbURL(track),
                            isCurrent: i == currentTrackIndex,
                            isDownloading: isDownloading,
                            isSeed: isSeed(track),
                            accentColor: accentColor
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        #endif
    }
}

private struct QueueRow: View {
    let track: Track
    let thumbURL: URL?
    let isCurrent: Bool
    let isDownloading: Bool
    let isSeed: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? .white : .white.opacity(0.75))

                Text(track.artist)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            if isSeed {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isCurrent ? accentColor.opacity(0.20) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            AlbumArt(url: thumbURL)

            if isCurrent {
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
