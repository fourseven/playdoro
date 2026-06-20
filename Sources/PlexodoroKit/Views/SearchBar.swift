import SwiftUI

struct SearchBar: View {
    @Binding var searchText: String
    let isSearching: Bool
    let searchResults: [Track]
    let searchError: String?
    let serverURL: String
    let token: String
    let selectedSeeds: [Track]
    let maxSeeds: Int
    let onSearch: (String) -> Void
    let onAdd: (Track) -> Void
    let onRemove: (Track) -> Void
    let onStart: ([Track]) -> Void
    var accentGradient: LinearGradient = Theme.accentGradient
    var accentColor: Color = Theme.accent

    private func thumbURL(for track: Track) -> URL? {
        guard let thumb = track.thumb else { return nil }
        return URL(string: "\(serverURL)\(thumb)?X-Plex-Token=\(token)")
    }

    private var selectedIds: Set<String> { Set(selectedSeeds.map(\.id)) }
    private var canAddMore: Bool { selectedSeeds.count < maxSeeds }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.55))
                TextField("Search for seed tracks…", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .tint(Theme.accent)
                    .onChange(of: searchText) { _, newValue in
                        onSearch(newValue)
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )

            if !selectedSeeds.isEmpty {
                seedChips
            }

            if isSearching {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if !searchResults.isEmpty {
                resultsList
            } else if let error = searchError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if !searchText.isEmpty && !isSearching {
                Text("No tracks found")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 60)
            }

            if !selectedSeeds.isEmpty {
                Button {
                    onStart(selectedSeeds)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Start with \(selectedSeeds.count) seed\(selectedSeeds.count == 1 ? "" : "s")")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white)
                    .background(accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: accentColor.opacity(0.35), radius: 14, x: 0, y: 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var seedChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectedSeeds) { track in
                    HStack(spacing: 6) {
                        AlbumArt(url: thumbURL(for: track))
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Text(track.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Button {
                            onRemove(track)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(searchResults) { track in
                    let isSelected = selectedIds.contains(track.id)
                    let canAdd = canAddMore && !isSelected
                    Button {
                        onAdd(track)
                    } label: {
                        HStack(spacing: 12) {
                            AlbumArt(url: thumbURL(for: track))
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text("\(track.artist) — \(track.album)")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                                .foregroundStyle(isSelected ? accentColor : (canAdd ? .white.opacity(0.85) : .white.opacity(0.3)))
                                .font(.title3)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd && !isSelected)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 260, alignment: .top)
    }
}
