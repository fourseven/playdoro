import Foundation
import Combine
import Logging

private let log = Logger(label: "com.plexodoro.appstate")

@MainActor
class AppState: ObservableObject {
    @Published var state: PomodoroState = .idle
    @Published var timeRemaining: TimeInterval = 25 * 60
    @Published var currentTrackTitle: String = ""
    @Published var errorMessage: String?

    @Published var connectionState: ConnectionState = .disconnected
    @Published var authCode: String = ""
    @Published var serverName: String = ""
    @Published var serverURL: String = ""
    @Published var token: String = ""
    @Published var isConfigured: Bool = false

    @Published var playlistTracks: [Track] = []
    @Published var currentTrackIndex: Int = 0
    @Published var isDownloading: Bool = false
    @Published var isPlaying: Bool = false
    @Published var seedTracks: [Track] = []
    @Published var savedPlaylists: [SeedPlaylist] = []

    var player = AudioPlayer()
    var client: (any MusicProvider)?
    #if canImport(UIKit)
    private let nowPlaying = NowPlayingCenter()
    #endif
    private let authManager = PlexAuthManager()
    private var timerSubscription: AnyCancellable?
    private var startTimerCancellable: AnyCancellable?
    private var isTimerPaused = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        let savedURL = UserDefaults.standard.string(forKey: UserDefaultsKey.serverURL) ?? ""
        let savedToken = UserDefaults.standard.string(forKey: UserDefaultsKey.plexToken) ?? ""
        let savedName = UserDefaults.standard.string(forKey: UserDefaultsKey.serverName) ?? ""

        if !savedToken.isEmpty {
            serverURL = savedURL
            token = savedToken
            serverName = savedName
            verifySavedConnection(token: savedToken)
        }

        savedPlaylists = Self.loadSavedPlaylists()
        loadSavedEQPreset()

        player.$isPlaying
            .assign(to: \.isPlaying, on: self)
            .store(in: &cancellables)
        player.$isPlaying
            .map { !$0 }
            .assign(to: \.isTimerPaused, on: self)
            .store(in: &cancellables)

        #if canImport(UIKit)
        nowPlaying.onTogglePlayPause = { [weak self] in self?.togglePlayback() }
        nowPlaying.setupRemoteCommands()
        player.$isPlaying
            .sink { [weak self] _ in self?.updateNowPlaying() }
            .store(in: &cancellables)
        #endif
    }

    // MARK: - OAuth Flow

    func connect() {
        Task {
            connectionState = .linking
            do {
                let pin = try await authManager.requestPin()
                authCode = pin.code

                let newToken = try await authManager.pollForAuth(pinId: pin.id)
                token = newToken
                UserDefaults.standard.set(newToken, forKey: UserDefaultsKey.plexToken)

                let (name, uris) = try await authManager.discoverServers(token: newToken)
                serverName = name
                UserDefaults.standard.set(name, forKey: UserDefaultsKey.serverName)

                connectionState = .discovering
                try await connectToServer(uris: uris, token: newToken)

                isConfigured = true
                connectionState = .connected
                errorMessage = nil
            } catch {
                let msg = error.localizedDescription
                log.error("Connect failed: \(msg)")
                connectionState = .failed(msg)
                errorMessage = msg
            }
        }
    }

    func cancelAuth() {
        connectionState = .disconnected
        authCode = ""
        errorMessage = nil
    }

    func disconnect() {
        client = nil
        isConfigured = false
        connectionState = .disconnected
        serverURL = ""
        token = ""
        serverName = ""
        authCode = ""
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.serverURL)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.plexToken)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.serverName)
    }

    private func verifySavedConnection(token: String) {
        Task { @MainActor in
            guard !isConfigured else { return }
            let savedURL = self.serverURL
            if !savedURL.isEmpty {
                let ok = await PlexClient.probe(serverURL: savedURL, token: token, timeout: 2.0)
                if ok {
                    let testClient = PlexClient(serverURL: savedURL, token: token)
                    do {
                        try await testClient.ping()
                        client = testClient
                        isConfigured = true
                        connectionState = .connected
                        errorMessage = nil
                        return
                    } catch {
                        log.info("Saved URL \(savedURL) probe ok but full ping failed, rediscovering…")
                    }
                } else {
                    log.info("Saved URL \(savedURL) unreachable, rediscovering…")
                }
            }
            await rediscover(token: token)
        }
    }

    private func rediscover(token: String) async {
        do {
            let (name, uris) = try await authManager.discoverServers(token: token)
            serverName = name
            UserDefaults.standard.set(name, forKey: UserDefaultsKey.serverName)
            try await connectToServer(uris: uris, token: token)
            isConfigured = true
            connectionState = .connected
        } catch {
            log.error("Rediscover failed: \(error.localizedDescription)")
            isConfigured = false
            connectionState = .disconnected
        }
    }

    /// Race all URIs in parallel; first probe to win takes it. Then build a real
    /// client and confirm with a full ping. Much faster than sequential probing
    /// when several candidate URIs are unreachable.
    private func connectToServer(uris: [String], token: String) async throws {
        if isConfigured {
            log.info("Already connected, skipping scan")
            return
        }

        log.info("Racing \(uris.count) candidate URIs in parallel…")
        guard let uri = await raceProbe(uris: uris, token: token) else {
            log.error("All \(uris.count) candidate URIs failed probe")
            throw PlexodoroError.serverUnreachable
        }

        log.info("Probe won at \(uri) — confirming with full ping")
        let testClient = PlexClient(serverURL: uri, token: token)
        do {
            try await testClient.ping()
        } catch {
            log.error("Probe-winner \(uri) failed full ping: \(error.localizedDescription)")
            throw error
        }

        serverURL = uri
        UserDefaults.standard.set(uri, forKey: UserDefaultsKey.serverURL)
        client = testClient
    }

    /// Race probe calls against all URIs. Returns the first URI that responds 2xx
    /// within `timeout`, cancelling the rest. nil if none succeed.
    private func raceProbe(uris: [String], token: String, timeout: TimeInterval = 2.0) async -> String? {
        await withTaskGroup(of: (uri: String, ok: Bool)?.self) { group in
            for uri in uris {
                group.addTask {
                    let ok = await PlexClient.probe(serverURL: uri, token: token, timeout: timeout)
                    return (uri: uri, ok: ok)
                }
            }
            var winner: String?
            for await result in group {
                if result?.ok == true && winner == nil {
                    winner = result?.uri
                    group.cancelAll()
                }
            }
            return winner
        }
    }

    // MARK: - Pomodoro

    func startPomodoro(seedTracks: [Track]) {
        guard state == .idle else { return }
        guard let client = client else {
            errorMessage = "Configure a music provider first"
            return
        }

        errorMessage = nil
        state = .running

        Task {
            do {
                let resolved = try await resolveSeedTracks(seedTracks: seedTracks, client: client)
                let (packed, urls, totalSeconds) = try await preparePackedTracks(seedTracks: resolved, client: client)
                self.seedTracks = resolved
                try await startPlayback(tracks: packed, urls: urls, totalSeconds: totalSeconds)
            } catch {
                errorMessage = error.localizedDescription
                state = .idle
            }
        }
    }

    func startPomodoro(savedPlaylist: SeedPlaylist) {
        startPomodoro(seedTracks: savedPlaylist.seeds)
    }

    // MARK: - Seed management

    var canAddMoreSeeds: Bool { seedTracks.count < PomodoroLimits.maxSeeds }

    func addSeed(_ track: Track) {
        guard canAddMoreSeeds, !seedTracks.contains(where: { $0.id == track.id }) else { return }
        seedTracks.append(track)
    }

    func removeSeed(_ track: Track) {
        seedTracks.removeAll { $0.id == track.id }
    }

    func clearSeeds() {
        seedTracks = []
    }

    // MARK: - Saved playlists

    private func recordPlaylist(seeds: [Track]) {
        guard !seeds.isEmpty else { return }
        let playlist = SeedPlaylist(seeds: seeds)
        savedPlaylists = mergeSavedPlaylists(
            existing: savedPlaylists,
            added: playlist,
            maxRetained: PomodoroLimits.savedPlaylistsMax
        )
        Self.persistSavedPlaylists(savedPlaylists)
    }

    private static func loadSavedPlaylists() -> [SeedPlaylist] {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKey.savedPlaylists) else { return [] }
        do {
            return try JSONDecoder().decode([SeedPlaylist].self, from: data)
        } catch {
            log.warning("Failed to decode savedPlaylists: \(error.localizedDescription)")
            return []
        }
    }

    private static func persistSavedPlaylists(_ playlists: [SeedPlaylist]) {
        do {
            let data = try JSONEncoder().encode(playlists)
            UserDefaults.standard.set(data, forKey: UserDefaultsKey.savedPlaylists)
        } catch {
            log.warning("Failed to encode savedPlaylists: \(error.localizedDescription)")
        }
    }

    private func configurePlayerCallbacks() {
        player.onTrackFinished = { [weak self] in
            self?.advanceToNextTrack()
        }
        player.onPlaylistFinished = { [weak self] in
            self?.finishAndReset()
        }
        player.onStoppedAtTrackEnd = { [weak self] in
            self?.finishAndReset()
        }
        player.onTrackDownloaded = { [weak self] track in
            guard let self = self else { return }
            if let idx = self.playlistTracks.firstIndex(where: { $0.id == track.id }) {
                self.playlistTracks[idx].isDownloaded = true
            }
        }
    }

    private func startPlayback(tracks: [Track], urls: [URL], totalSeconds: TimeInterval) async throws {
        configurePlayerCallbacks()

        timeRemaining = totalSeconds
        playlistTracks = tracks
        currentTrackIndex = 0
        currentTrackTitle = tracks.first.map { "\($0.artist) — \($0.title)" } ?? ""

        startTimerCancellable = player.$isPlaying
            .filter { $0 }
            .first()
            .sink { [weak self] _ in
                self?.startTimer(duration: totalSeconds)
            }

        isDownloading = true
        playlistTracks = await player.downloadAndPlay(tracks: tracks, urls: urls)
        isDownloading = false

        guard state == .running else { return }

        if playlistTracks.isEmpty {
            errorMessage = "No tracks could be downloaded"
            timerSubscription?.cancel()
            state = .idle
            return
        }

        recordPlaylist(seeds: self.seedTracks)
    }

    private func advanceToNextTrack() {
        let nextIndex = currentTrackIndex + 1
        guard nextIndex < playlistTracks.count else {
            finishAndReset()
            return
        }
        currentTrackIndex = nextIndex
        let track = playlistTracks[nextIndex]
        currentTrackTitle = "\(track.artist) — \(track.title)"
        #if canImport(UIKit)
        updateNowPlaying()
        #endif
    }

    #if canImport(UIKit)
    private func updateNowPlaying() {
        guard state == .running, playlistTracks.indices.contains(currentTrackIndex) else {
            nowPlaying.clear()
            return
        }
        let track = playlistTracks[currentTrackIndex]
        // Use the decoded-audio timeline so the scrubber baseline and duration
        // share one clock; fall back to the provider duration before playback
        // has decoded a file.
        let durationSeconds = player.currentDuration > 0 ? player.currentDuration : track.duration / 1000
        nowPlaying.update(
            title: track.title,
            artist: track.artist,
            album: track.album,
            durationSeconds: durationSeconds,
            elapsedSeconds: player.currentElapsed,
            isPlaying: player.isPlaying,
            artworkURL: client?.thumbURL(for: track)
        )
    }
    #endif

    private func resolveSeedTracks(seedTracks: [Track], client: any MusicProvider) async throws -> [Track] {
        try await withThrowingTaskGroup(of: Track.self) { group in
            for seed in seedTracks {
                group.addTask {
                    guard let track = try await client.getTrack(id: seed.id) else {
                        throw PlexodoroError.trackUnavailable
                    }
                    return track
                }
            }
            var resolved: [Track] = []
            for try await track in group { resolved.append(track) }
            return resolved
        }
    }

    private func preparePackedTracks(seedTracks: [Track], client: any MusicProvider) async throws -> (packed: [Track], urls: [URL], totalSeconds: TimeInterval) {
        let nearest = try await client.getNearest(
            trackIds: seedTracks.map(\.id),
            limit: PomodoroConfig.default.maxCandidates
        )
        let engine = PomodoroEngine()
        var packed = engine.pack(tracks: nearest, mustInclude: seedTracks)
        packed = deduplicate(tracks: packed)
        packed.shuffle()
        let totalSeconds = engine.totalDuration(of: packed)

        let urls: [URL] = packed.compactMap { client.streamURL(for: $0) }

        guard urls.count == packed.count else {
            throw PlexodoroError.noAudioURL
        }

        return (packed, urls, totalSeconds)
    }

    private func finishAndReset() {
        Task { @MainActor in
            timerSubscription?.cancel()
            state = .finished
            player.stop()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            resetState()
        }
    }

    func stopPomodoro() {
        state = .stopping
        timerSubscription?.cancel()
        player.stop()
        resetState()
    }

    func togglePlayback() {
        player.togglePlayPause()
    }

    func applyEQ(preset: EQPreset) {
        player.applyEQ(preset: preset)
        UserDefaults.standard.set(preset.id, forKey: UserDefaultsKey.eqPresetID)
    }

    var currentEQPreset: EQPreset {
        player.currentEQPreset
    }

    private func loadSavedEQPreset() {
        let savedID = UserDefaults.standard.string(forKey: UserDefaultsKey.eqPresetID)
        let preset = EQPreset.settingsPresets.first { $0.id == savedID } ?? .flat
        player.applyEQ(preset: preset)
    }

    private func startTimer(duration: TimeInterval) {
        timeRemaining = duration
        timerSubscription = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.state == .running, !self.isTimerPaused else { return }
                self.timeRemaining -= 1
                if self.timeRemaining <= 0 {
                    self.timeRemaining = 0
                    self.handleTimerFinished()
                }
            }
    }

    private func handleTimerFinished() {
        state = .stopping
        timerSubscription?.cancel()
        player.stopAfterCurrentTrack()
    }

    private func resetState() {
        state = .idle
        #if canImport(UIKit)
        nowPlaying.clear()
        #endif
        timeRemaining = 25 * 60
        currentTrackTitle = ""
        playlistTracks = []
        currentTrackIndex = 0
        seedTracks = []
        errorMessage = nil
        startTimerCancellable?.cancel()
        startTimerCancellable = nil
    }

    var formattedTime: String {
        let mins = Int(timeRemaining) / 60
        let secs = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Connection State

extension AppState {
    enum ConnectionState: Equatable {
        case disconnected
        case linking
        case discovering
        case connected
        case failed(String)
    }
}
