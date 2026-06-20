import SwiftUI

struct ContentView: View {
    @ObservedObject var appState: AppState
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var searchResults: [Track] = []
    @State private var searchError: String?
    @State private var isSearching = false
    @State private var searchTaskID = UUID()

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    #if os(macOS)
    private var macBody: some View {
        VStack(spacing: 12) {
            if showSettings {
                settingsContent
            } else {
                mainContent
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
    #endif

    #if os(iOS)
    private var iosBody: some View {
        mainContent
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    settingsContent
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSettings = false }
                            }
                        }
                }
                .preferredColorScheme(.dark)
            }
    }
    #endif

    @ViewBuilder
    private var mainContent: some View {
        if !appState.isConfigured {
            connectionContent
        } else if appState.state == .idle {
            idleView
        } else {
            activeView
        }
    }

    @ViewBuilder
    private var connectionContent: some View {
        switch appState.connectionState {
        case .disconnected:
            ConnectView {
                appState.connect()
            }
        case .linking:
            LinkingView(code: appState.authCode) {
                appState.cancelAuth()
            }
        case .discovering:
            DiscoveringView()
        case .connected:
            ConnectView {
                appState.connect()
            }
        case .failed(let message):
            FailedView(message: message) {
                appState.connect()
            } onCancel: {
                appState.cancelAuth()
            }
        }
    }

    private var idleView: some View {
        ZStack {
            AlbumArtBackdrop(url: idleBackdropURL)

            ScrollView {
                VStack(spacing: 24) {
                    headerBlock
                        .padding(.top, 24)

                    if !appState.savedPlaylists.isEmpty {
                        RecentPlaylistsView(
                            playlists: appState.savedPlaylists,
                            serverURL: appState.serverURL,
                            token: appState.token,
                            onTap: { playlist in
                                appState.startPomodoro(savedPlaylist: playlist)
                            }
                        )
                    }

                    SearchBar(
                        searchText: $searchText,
                        isSearching: isSearching,
                        searchResults: searchResults,
                        searchError: searchError,
                        serverURL: appState.serverURL,
                        token: appState.token,
                        selectedSeeds: appState.seedTracks,
                        maxSeeds: PomodoroLimits.maxSeeds,
                        onSearch: searchDebounce,
                        onAdd: { track in
                            appState.addSeed(track)
                            searchText = ""
                            searchResults = []
                        },
                        onRemove: appState.removeSeed,
                        onStart: { seeds in
                            appState.startPomodoro(seedTracks: seeds)
                        }
                    )

                    if appState.seedTracks.isEmpty {
                        Button {
                            appState.startPomodoro()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "play.fill")
                                Text("Start from current track")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .foregroundStyle(.white)
                            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Theme.accent.opacity(0.35), radius: 14, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                    }

                    if let error = appState.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var headerBlock: some View {
        VStack(spacing: 6) {
            Text("Plexodoro")
                .font(Theme.titleFont)
                .foregroundStyle(.white)
            Text("Focus with your library")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var idleBackdropURL: URL? {
        if let playlist = appState.savedPlaylists.first,
           let seed = playlist.seeds.first,
           let thumb = seed.thumb {
            return URL(string: "\(appState.serverURL)\(thumb)?X-Plex-Token=\(appState.token)")
        }
        return nil
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

    @MainActor
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
