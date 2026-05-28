import Foundation
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var state: PomodoroState = .idle
    @Published var timeRemaining: TimeInterval = 25 * 60
    @Published var currentTrackTitle: String = ""
    @Published var errorMessage: String?
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: UserDefaultsKey.serverURL) }
    }
    @Published var token: String {
        didSet { UserDefaults.standard.set(token, forKey: UserDefaultsKey.plexToken) }
    }
    @Published var isConfigured: Bool = false
    @Published var playlistTracks: [Track] = []
    @Published var currentTrackIndex: Int = 0
    @Published var isDownloading: Bool = false

    let player = AudioPlayer()
    var client: PlexClient?
    private var timerSubscription: AnyCancellable?
    private var isTimerPaused = false

    init() {
        let savedURL = UserDefaults.standard.string(forKey: UserDefaultsKey.serverURL) ?? "https://your-plex-server:32400"
        let savedToken = UserDefaults.standard.string(forKey: UserDefaultsKey.plexToken) ?? ""
        self.serverURL = savedURL
        self.token = savedToken
        self.isConfigured = !savedToken.isEmpty

        if isConfigured {
            self.client = PlexClient(serverURL: savedURL, token: savedToken)
        }
    }

    func updateCredentials(serverURL: String, token: String) {
        self.serverURL = serverURL
        self.token = token
        self.client = PlexClient(serverURL: serverURL, token: token)

        Task {
            do {
                try await client?.ping()
                isConfigured = true
                errorMessage = nil
            } catch {
                isConfigured = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func startPomodoro() {
        startPomodoro(seedTrackId: nil)
    }

    func startPomodoro(seedTrackId: String?) {
        guard state == .idle else { return }
        guard let client = client else {
            errorMessage = "Configure your Plex server first"
            return
        }

        errorMessage = nil
        state = .running

        Task {
            do {
                let seedTrack = try await resolveSeedTrack(seedTrackId: seedTrackId, client: client)
                let (packed, urls, totalSeconds) = try await preparePackedTracks(seedTrack: seedTrack, client: client)

                player.onTrackFinished = { [weak self] in
                    self?.advanceToNextTrack()
                }
                player.onPlaylistFinished = { [weak self] in
                    self?.finishAndReset()
                }
                player.onStoppedAtTrackEnd = { [weak self] in
                    self?.finishAndReset()
                }

                timeRemaining = totalSeconds
                // Show the full shuffled playlist immediately
                playlistTracks = packed
                currentTrackIndex = 0
                if let first = packed.first {
                    currentTrackTitle = "\(first.artist) — \(first.title)"
                }

                isDownloading = true
                let localURLs = await player.download(tracks: packed, urls: urls)
                isDownloading = false

                // Filter to successfully downloaded tracks only
                let downloadedIndices = localURLs.enumerated().compactMap { $1 != nil ? $0 : nil }
                playlistTracks = downloadedIndices.map { packed[$0] }
                currentTrackIndex = 0
                if let first = playlistTracks.first {
                    currentTrackTitle = "\(first.artist) — \(first.title)"
                }

                guard !playlistTracks.isEmpty else {
                    errorMessage = "No tracks could be downloaded"
                    state = .idle
                    return
                }

                let validURLs = localURLs.compactMap { $0 }
                await player.play(urls: validURLs)
                startTimer(duration: totalSeconds)
            } catch {
                errorMessage = error.localizedDescription
                state = .idle
            }
        }
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
    }

    private func resolveSeedTrack(seedTrackId: String?, client: PlexClient) async throws -> Track {
        if let seedTrackId {
            guard let track = try await client.getTrack(id: seedTrackId) else {
                throw PlexodoroError.noCurrentTrack
            }
            return track
        }
        guard let session = try await client.getSessions() else {
            throw PlexodoroError.noCurrentTrack
        }
        return session.track
    }

    private func preparePackedTracks(seedTrack: Track, client: PlexClient) async throws -> (packed: [Track], urls: [URL], totalSeconds: TimeInterval) {
        let nearest = try await client.getNearest(trackId: seedTrack.id, limit: PomodoroConfig.default.maxCandidates)
        let withoutSeed = nearest.filter { $0.id != seedTrack.id }
        let engine = PomodoroEngine()
        // Subtract seed track duration so the total (including seed) lands near 25 min
        let seedSec = seedTrack.duration / 1000
        let adjustedTarget = max(PomodoroConfig.default.targetDuration - seedSec, PomodoroConfig.default.tolerance)
        var packed = engine.pack(tracks: withoutSeed, target: adjustedTarget)
        packed = deduplicate(tracks: packed)
        packed.append(seedTrack)
        packed.shuffle()
        let totalSeconds = engine.totalDuration(of: packed)

        let urls: [URL] = packed.compactMap { track in
            guard !track.key.isEmpty else { return nil }
            return client.streamURL(for: track)
        }

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
        isTimerPaused = false
        player.stop()
        resetState()
    }

    func togglePlayback() {
        player.togglePlayPause()
        isTimerPaused = !player.isPlaying
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
        timeRemaining = 25 * 60
        currentTrackTitle = ""
        playlistTracks = []
        currentTrackIndex = 0
        errorMessage = nil
    }

    var formattedTime: String {
        let mins = Int(timeRemaining) / 60
        let secs = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
