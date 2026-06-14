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

    private func thumbURL(for track: Track) -> URL? {
        guard let thumb = track.thumb else { return nil }
        return URL(string: "\(serverURL)\(thumb)?X-Plex-Token=\(token)")
    }

    private var selectedIds: Set<String> { Set(selectedSeeds.map(\.id)) }
    private var canAddMore: Bool { selectedSeeds.count < maxSeeds }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search for seed tracks…", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, newValue in
                        onSearch(newValue)
                    }
            }
            .padding(8)
            .background(Color(.systemFill))
            .cornerRadius(6)

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
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if !searchText.isEmpty && !isSearching {
                Text("No tracks found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }

            if !selectedSeeds.isEmpty {
                Button {
                    onStart(selectedSeeds)
                } label: {
                    Label("Start with \(selectedSeeds.count) seed\(selectedSeeds.count == 1 ? "" : "s")",
                          systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var seedChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(selectedSeeds) { track in
                    HStack(spacing: 4) {
                        AlbumArt(url: thumbURL(for: track))
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        Text(track.title)
                            .font(.caption)
                            .lineLimit(1)
                        Button {
                            onRemove(track)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(4)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(searchResults) { track in
                    let isSelected = selectedIds.contains(track.id)
                    let canAdd = canAddMore && !isSelected
                    Button {
                        onAdd(track)
                    } label: {
                        HStack(spacing: 8) {
                            AlbumArt(url: thumbURL(for: track))
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(track.title)
                                    .font(.body)
                                    .lineLimit(1)
                                Text("\(track.artist) — \(track.album)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                                .foregroundColor(isSelected ? .green : (canAdd ? .accentColor : .secondary))
                                .font(.title3)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd && !isSelected)
                    .background(Color(.systemFill))
                    .cornerRadius(4)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 240, alignment: .top)
    }
}
