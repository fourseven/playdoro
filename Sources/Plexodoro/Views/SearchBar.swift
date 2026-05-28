import SwiftUI

struct SearchBar: View {
    @Binding var searchText: String
    let isSearching: Bool
    let searchResults: [Track]
    let searchError: String?
    let serverURL: String
    let token: String
    let onSearch: (String) -> Void
    let onSelect: (Track) -> Void

    private func thumbURL(for track: Track) -> URL? {
        guard let thumb = track.thumb else { return nil }
        return URL(string: "\(serverURL)\(thumb)?X-Plex-Token=\(token)")
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search for a seed track…", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { newValue in
                        onSearch(newValue)
                    }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)

            if isSearching {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity)
            } else if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(searchResults) { track in
                            Button {
                                onSelect(track)
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
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                        }
                    }
                }
                .frame(maxHeight: 200)
            } else if let error = searchError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else if !searchText.isEmpty && !isSearching {
                Text("No tracks found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
