import Foundation
import Combine
import Logging

private let log = Logger(label: AppIdentity.key("appstate"))

@MainActor
class AppState: ObservableObject {
    @Published var state: PomodoroState = .idle
    @Published var timeRemaining: TimeInterval = 25 * 60
    @Published var currentTrackTitle: String = ""
    @Published var errorMessage: String?
    @Published var sessionWarning: String?

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
    @Published var recentEQPresetIDs: [String] = []
    @Published var variety: Double = PomodoroConfig.default.variety

    var catalog: (any MusicCatalog)?
    @Published var backend: (any PlaybackBackend)?
    @Published var currentProgress: Double = 0
    @Published var volume: Float = 1.0
    private let nowPlaying = NowPlayingCenter()
    private let authManager = PlexAuthManager()
    private var timerSubscription: AnyCancellable?
    private var backendCancellable: AnyCancellable?
    private var isTimerPaused = false
    private var cancellables = Set<AnyCancellable>()
    private var playbackReportTimer: Timer?
    private var pendingTimerStart = false
    private var pendingTimerDuration: TimeInterval = 0
    private var lastSyncedIsPlaying = false
    private var pendingEQPreset: EQPreset?
    private var pendingEQEnabled = true

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

        let savedVariety = UserDefaults.standard.object(forKey: UserDefaultsKey.variety) as? Double
        if let savedVariety { variety = savedVariety }

        savedPlaylists = Self.loadSavedPlaylists()
        recentEQPresetIDs = UserDefaults.standard.stringArray(forKey: UserDefaultsKey.recentEQPresetIDs) ?? []
        loadSavedEQPreset()

        nowPlaying.onTogglePlayPause = { [weak self] in self?.togglePlayback() }
        nowPlaying.setupRemoteCommands()
    }

    // MARK: - Backend lifecycle

    private func setPlexProvider(_ plex: PlexClient) {
        catalog = plex
        let newBackend = EnginePlaybackBackend(provider: plex)
        backend = newBackend
        bindBackend(newBackend)
    }

    fileprivate func bindBackend(_ newBackend: any PlaybackBackend) {
        backendCancellable?.cancel()
        configurePlaybackCallbacks(newBackend)
        backendCancellable = newBackend.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.syncFromBackend()
            }
        }
        applyPendingEQ()
    }

    @MainActor
    private func syncFromBackend() {
        guard let backend = backend else { return }
        let isPlaying = backend.isPlaying
        isTimerPaused = !isPlaying
        currentProgress = backend.currentProgress
        if let volumeProvider = backend as? any VolumeProviding {
            volume = volumeProvider.volume
        }
        guard isPlaying != lastSyncedIsPlaying else { return }
        lastSyncedIsPlaying = isPlaying
        handlePlaybackStateChange(isPlaying)
        // Feed the system card on both transitions — macOS keys its media-key
        // ownership off `playbackState`, so pausing must publish `.paused`.
        updateNowPlaying()
        if isPlaying {
            if pendingTimerStart {
                pendingTimerStart = false
                startTimer(duration: pendingTimerDuration)
            }
        }
    }

    private func applyPendingEQ() {
        guard let eq = backend as? any EQProviding else { return }
        if let preset = pendingEQPreset {
            eq.applyEQ(preset: preset)
        }
        eq.setEQEnabled(pendingEQEnabled)
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

                let (name, endpoints) = try await authManager.discoverServers(token: newToken)
                serverName = name
                UserDefaults.standard.set(name, forKey: UserDefaultsKey.serverName)

                connectionState = .discovering
                try await connectToServer(endpoints: endpoints, token: newToken)

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
        backend?.stop()
        backendCancellable?.cancel()
        backend = nil
        catalog = nil
        isConfigured = false
        connectionState = .disconnected
        serverURL = ""
        token = ""
        serverName = ""
        authCode = ""
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.serverURL)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.plexToken)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.serverName)
        CertDelegate.clearAllStoredPins()
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
                        setPlexProvider(testClient)
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
            let (name, endpoints) = try await authManager.discoverServers(token: token)
            serverName = name
            UserDefaults.standard.set(name, forKey: UserDefaultsKey.serverName)
            try await connectToServer(endpoints: endpoints, token: token)
            isConfigured = true
            connectionState = .connected
        } catch {
            log.error("Rediscover failed: \(error.localizedDescription)")
            isConfigured = false
            connectionState = .disconnected
        }
    }

    /// Race the endpoints in two waves, preferring Plex-local connections so
    /// downloads ride the LAN path instead of the flaky public/WAN hairpin route.
    /// Local probes race for up to `timeout`; only if none respond do we fall
    /// back to the remote URIs. The winner is then confirmed with a full ping.
    private func connectToServer(endpoints: [PlexServerEndpoint], token: String) async throws {
        if isConfigured {
            log.info("Already connected, skipping scan")
            return
        }

        let local = endpoints.filter { $0.isLocal }.map(\.uri)
        let remote = endpoints.filter { !$0.isLocal }.map(\.uri)
        log.info("Racing \(endpoints.count) candidate URIs, preferring \(local.count) local over \(remote.count) remote…")

        var uri: String?
        if local.isEmpty {
            uri = await raceProbe(uris: remote, token: token, timeout: 2.0)
        } else if let localWinner = await raceProbe(uris: local, token: token, timeout: 2.0) {
            uri = localWinner
            log.info("Local probe won at \(localWinner)")
        } else {
            log.info("No local candidate responded — falling back to \(remote.count) remote URIs")
            uri = await raceProbe(uris: remote, token: token, timeout: 2.0)
        }

        guard let uri else {
            log.error("All \(endpoints.count) candidate URIs failed probe")
            throw PlaydoroError.serverUnreachable
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
        setPlexProvider(testClient)
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
        guard let catalog = catalog, backend != nil else {
            errorMessage = "Configure a music provider first"
            return
        }

        errorMessage = nil
        sessionWarning = nil
        state = .running

        Task {
            do {
                let resolved = try await resolveSeedTracks(seedTracks: seedTracks, catalog: catalog)
                let (packed, totalSeconds) = try await preparePackedTracks(seedTracks: resolved, catalog: catalog)
                self.seedTracks = resolved
                try await startPlayback(tracks: packed, totalSeconds: totalSeconds)
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

    private func configurePlaybackCallbacks(_ playbackBackend: any PlaybackBackend) {
        playbackBackend.onTrackFinished = { [weak self] track in
            self?.reportCompletedPlay(track)
            self?.advanceToNextTrack()
            self?.reportCurrentPlayback(.playing)
        }
        playbackBackend.onPlaylistFinished = { [weak self] track in
            if let track {
                self?.reportCompletedPlay(track)
            }
            self?.finishAndReset()
        }
        playbackBackend.onStoppedAtTrackEnd = { [weak self] track in
            if let track {
                self?.reportCompletedPlay(track)
            }
            self?.finishAndReset()
        }
        playbackBackend.onTrackDownloaded = { [weak self] track in
            guard let self = self else { return }
            if let idx = self.playlistTracks.firstIndex(where: { $0.id == track.id }) {
                self.playlistTracks[idx].isDownloaded = true
            }
        }
    }

    /// Report a fully-played track at full duration — Plex treats a stopped
    /// timeline at >= duration as "watched" and Tautulli records the session.
    private func reportCompletedPlay(_ track: Track) {
        reportTrackPlayback(track: track, time: Double(track.duration) / 1000, playState: .stopped)
    }

    /// Report the currently-playing track's live position/state. Fire-and-forget —
    /// network failures must never interrupt the session.
    private func reportCurrentPlayback(_ playState: PlaybackState) {
        guard state == .running, catalog != nil, let track = currentPlayingTrack else { return }
        let duration = Double(track.duration) / 1000
        reportTrackPlayback(track: track, time: min(backend?.currentElapsed ?? 0, duration), playState: playState)
    }

    private func reportTrackPlayback(track: Track, time: TimeInterval, playState: PlaybackState) {
        guard let catalog = catalog else { return }
        let duration = Double(track.duration) / 1000
        Task {
            do {
                try await catalog.reportPlayback(for: track, time: time, duration: duration, state: playState)
            } catch {
                log.warning("Timeline report failed for \(track.title): \(error.localizedDescription)")
            }
        }
    }

    private var currentPlayingTrack: Track? {
        guard playlistTracks.indices.contains(currentTrackIndex) else { return nil }
        return playlistTracks[currentTrackIndex]
    }

    private func handlePlaybackStateChange(_ isPlaying: Bool) {
        guard state == .running, catalog != nil else { return }
        if isPlaying {
            startPlaybackReportTimer()
            reportCurrentPlayback(.playing)
        } else {
            stopPlaybackReportTimer()
            reportCurrentPlayback(.paused)
        }
    }

    /// Slow heartbeat that keeps the Plex timeline session alive and the current
    /// position advancing in Tautulli while a track runs. Position ticks also
    /// give pause/resume a valid `time` baseline.
    private func startPlaybackReportTimer() {
        stopPlaybackReportTimer()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reportCurrentPlayback(.playing)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackReportTimer = timer
    }

    private func stopPlaybackReportTimer() {
        playbackReportTimer?.invalidate()
        playbackReportTimer = nil
    }

    private func startPlayback(tracks: [Track], totalSeconds: TimeInterval) async throws {
        guard let backend = backend else { throw PlaydoroError.playbackFailed }

        timeRemaining = totalSeconds
        playlistTracks = tracks
        currentTrackIndex = 0
        currentTrackTitle = tracks.first.map { "\($0.artist) — \($0.title)" } ?? ""

        pendingTimerStart = true
        pendingTimerDuration = totalSeconds
        // Timer starts on the first play event from the backend — same
        // semantics as the old first-isPlaying sink, but provider-agnostic.
        isTimerPaused = true

        isDownloading = true
        defer { isDownloading = false }
        let playedTracks = try await backend.play(tracks: tracks, totalSeconds: totalSeconds)
        pendingTimerStart = false

        guard state == .running else { return }

        if playedTracks.isEmpty {
            errorMessage = "No tracks could be played"
            timerSubscription?.cancel()
            state = .idle
            return
        }

        playlistTracks = playedTracks

        // Rebase the pomodoro clock onto the tracks that actually played:
        // the timer was started from the PLANNED total when playback began, so
        // fold in the time already counted and measure the remainder against
        // the real playlist length, not the ideal one.
        let elapsed = min(totalSeconds, max(0, totalSeconds - timeRemaining))
        let actualTotal = playedTracks.reduce(TimeInterval(0)) { $0 + $1.duration / 1000 }
        timeRemaining = max(0, actualTotal - elapsed)

        let missing = tracks.count - playedTracks.count
        if missing > 0 {
            sessionWarning = "\(missing) of \(tracks.count) tracks couldn't be played — playing \(playedTracks.count)"
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
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard state == .running, playlistTracks.indices.contains(currentTrackIndex) else {
            nowPlaying.clear()
            return
        }
        let track = playlistTracks[currentTrackIndex]
        // Use the decoded-audio timeline so the scrubber baseline and duration
        // share one clock; fall back to the provider duration before playback
        // has decoded a file.
        let backend = self.backend
        let durationSeconds = backend?.currentDuration ?? 0
        let resolvedDuration = durationSeconds > 0 ? durationSeconds : track.duration / 1000
        nowPlaying.update(
            title: track.title,
            artist: track.artist,
            album: track.album,
            durationSeconds: resolvedDuration,
            elapsedSeconds: backend?.currentElapsed ?? 0,
            isPlaying: backend?.isPlaying ?? false,
            artworkURL: catalog?.thumbURL(for: track)
        )
    }

    private func resolveSeedTracks(seedTracks: [Track], catalog: any MusicCatalog) async throws -> [Track] {
        try await withThrowingTaskGroup(of: Track.self) { group in
            for seed in seedTracks {
                group.addTask {
                    guard let track = try await catalog.getTrack(id: seed.id) else {
                        throw PlaydoroError.trackUnavailable
                    }
                    return track
                }
            }
            var resolved: [Track] = []
            for try await track in group { resolved.append(track) }
            return resolved
        }
    }

    private func preparePackedTracks(seedTracks: [Track], catalog: any MusicCatalog) async throws -> (packed: [Track], totalSeconds: TimeInterval) {
        let nearest = try await catalog.getNearest(
            trackIds: seedTracks.map(\.id),
            limit: PomodoroConfig.default.maxCandidates
        )
        let engine = PomodoroEngine(config: PomodoroConfig(variety: variety))
        let candidates = deduplicateForPacking(candidates: nearest, seeds: seedTracks)
        var packed = engine.pack(tracks: candidates, mustInclude: seedTracks)
        packed.shuffle()
        let totalSeconds = engine.totalDuration(of: packed)
        return (packed, totalSeconds)
    }

    private func finishAndReset() {
        Task { @MainActor in
            timerSubscription?.cancel()
            state = .finished
            backend?.stop()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            resetState()
        }
    }

    func stopPomodoro() {
        state = .stopping
        timerSubscription?.cancel()
        // Partial play: end the Plex session at the current position so Tautulli
        // records the partial track instead of losing it.
        if catalog != nil, let track = currentPlayingTrack {
            let duration = Double(track.duration) / 1000
            reportTrackPlayback(track: track, time: min(backend?.currentElapsed ?? 0, duration), playState: .stopped)
        }
        stopPlaybackReportTimer()
        backend?.stop()
        resetState()
    }

    func togglePlayback() {
        backend?.togglePlayPause()
    }

    func setVolume(_ value: Float) {
        let clamped = min(max(value, 0), 1)
        if let provider = backend as? any VolumeProviding {
            provider.volume = clamped
        }
        volume = clamped
    }

    var supportsEQ: Bool {
        backend?.capabilities.contains(.eq) ?? false
    }

    var supportsVolume: Bool {
        backend?.capabilities.contains(.volume) ?? false
    }

    private var eqProvider: (any EQProviding)? {
        backend as? any EQProviding
    }

    func applyEQ(preset: EQPreset) {
        eqProvider?.applyEQ(preset: preset)
        UserDefaults.standard.set(preset.id, forKey: UserDefaultsKey.eqPresetID)
        recordRecentEQPreset(preset)
    }

    /// Prepend the preset to the recents list (skip Flat — "EQ off" isn't a
    /// headphone swap worth pinning to the top).
    private func recordRecentEQPreset(_ preset: EQPreset) {
        guard preset.id != "flat" else { return }
        let updated = mergeRecentEQPresets(
            existing: recentEQPresetIDs,
            added: preset.id,
            maxRetained: PomodoroLimits.recentEQPresetsMax
        )
        guard updated != recentEQPresetIDs else { return }
        recentEQPresetIDs = updated
        UserDefaults.standard.set(updated, forKey: UserDefaultsKey.recentEQPresetIDs)
    }

    /// Recently-used presets resolved to their full values, in most-recent-first
    /// order. Stale IDs (deleted/renamed presets) resolve to `.flat` and are
    /// filtered out, so the section silently self-heals.
    var recentEQPresets: [EQPreset] {
        recentEQPresetIDs
            .map { EQPreset.resolve(id: $0) }
            .filter { $0.id != "flat" }
    }

    var currentEQPreset: EQPreset {
        eqProvider?.currentEQPreset ?? pendingEQPreset ?? .flat
    }

    func setEQEnabled(_ enabled: Bool) {
        eqProvider?.setEQEnabled(enabled)
        UserDefaults.standard.set(enabled, forKey: UserDefaultsKey.eqEnabled)
    }

    var eqEnabled: Bool {
        eqProvider?.eqEnabled ?? true
    }

    func setVariety(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        variety = clamped
        UserDefaults.standard.set(clamped, forKey: UserDefaultsKey.variety)
    }

    private func loadSavedEQPreset() {
        let savedID = UserDefaults.standard.string(forKey: UserDefaultsKey.eqPresetID)
        pendingEQPreset = EQPreset.resolve(id: savedID)

        // UserDefaults stores Bool as NSNumber/Any; default to true if absent.
        pendingEQEnabled = UserDefaults.standard.object(forKey: UserDefaultsKey.eqEnabled) as? Bool ?? true
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
        backend?.stopAfterCurrentTrack()
    }

    private func resetState() {
        state = .idle
        nowPlaying.clear()
        timeRemaining = 25 * 60
        currentTrackTitle = ""
        playlistTracks = []
        currentTrackIndex = 0
        seedTracks = []
        errorMessage = nil
        sessionWarning = nil
        stopPlaybackReportTimer()
        pendingTimerStart = false
        lastSyncedIsPlaying = false
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
