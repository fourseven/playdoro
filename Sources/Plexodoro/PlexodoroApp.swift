import SwiftUI

@main
struct PlexodoroApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Plexodoro", systemImage: appState.state == .running ? "timer" : "timer") {
            ContentView(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @ObservedObject var appState: AppState
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var searchResults: [Track] = []
    @State private var searchError: String?
    @State private var isSearching = false
    @State private var searchTaskID = UUID()

    var body: some View {
        VStack(spacing: 12) {
            if showSettings {
                settingsContent
            } else if !appState.isConfigured {
                VStack(spacing: 8) {
                    Text("Plexodoro")
                        .font(.headline)
                    Text("Configure your Plex server in Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if appState.state == .idle {
                idleView
            } else {
                activeView
            }

            Divider()

            if showSettings {
                Button("Done") {
                    showSettings = false
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 12) {
                    Button("Settings…") {
                        showSettings = true
                    }
                    .buttonStyle(.plain)
                    .font(.caption)

                    Spacer()

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
            }
        }
        .padding()
        .frame(width: 300)
    }

    private var idleView: some View {
        VStack(spacing: 10) {
            SearchBar(
                searchText: $searchText,
                isSearching: isSearching,
                searchResults: searchResults,
                searchError: searchError,
                onSearch: searchDebounce,
                onSelect: { appState.startPomodoro(seedTrackId: $0.id) }
            )

            Divider()

            Button {
                appState.startPomodoro(seedTrackId: nil)
            } label: {
                Label("Start from current track", systemImage: "play.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var activeView: some View {
        ActiveSessionView(appState: appState, serverURL: appState.serverURL, token: appState.token)
    }

    private var settingsContent: some View {
        SettingsView(appState: appState)
    }

    private func searchDebounce(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }

        searchError = nil
        let taskID = UUID()
        searchTaskID = taskID
        isSearching = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard taskID == searchTaskID else { return }
            await performSearch(query: trimmed, taskID: taskID)
        }
    }

    private func performSearch(query: String, taskID: UUID) async {
        guard let client = appState.client else { return }

        do {
            let results = try await client.searchTracks(query: query)
            guard taskID == searchTaskID else { return }
            searchResults = results
            isSearching = false
        } catch {
            guard taskID == searchTaskID else { return }
            searchResults = []
            searchError = error.localizedDescription
            isSearching = false
        }
    }
}

private struct SearchBar: View {
    @Binding var searchText: String
    let isSearching: Bool
    let searchResults: [Track]
    let searchError: String?
    let onSearch: (String) -> Void
    let onSelect: (Track) -> Void

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

private struct ActiveSessionView: View {
    @ObservedObject var appState: AppState
    let serverURL: String
    let token: String

    var body: some View {
        VStack(spacing: 6) {
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

            if appState.isDownloading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Downloading tracks…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !appState.playlistTracks.isEmpty {
                Divider()
                PlaylistView(
                    tracks: appState.playlistTracks,
                    currentTrackIndex: appState.currentTrackIndex,
                    isDownloading: appState.isDownloading
                )
            }

            HStack(spacing: 12) {
                if !appState.isDownloading {
                    Button {
                        appState.togglePlayback()
                    } label: {
                        Image(systemName: appState.player.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Stop") {
                        appState.stopPomodoro()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
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
}

private struct PlaylistView: View {
    let tracks: [Track]
    let currentTrackIndex: Int
    let isDownloading: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                    HStack(spacing: 4) {
                        if isDownloading {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                        } else if i == currentTrackIndex {
                            Image(systemName: "play.fill")
                                .font(.system(size: 7))
                                .foregroundColor(.green)
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
    }
}

private struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            TextField("Plex Server URL", text: $appState.serverURL)
                .textFieldStyle(.roundedBorder)

            SecureField("Plex Token", text: $appState.token)
                .textFieldStyle(.roundedBorder)

            HStack {
                if appState.isConfigured {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if !appState.token.isEmpty {
                    Label("Not connected", systemImage: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                }

                Spacer()

                Button("Test Connection") {
                    appState.updateCredentials(
                        serverURL: appState.serverURL,
                        token: appState.token
                    )
                }
            }

            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}
