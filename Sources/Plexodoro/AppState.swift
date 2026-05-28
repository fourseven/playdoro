import Foundation
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var state: PomodoroState = .idle
    @Published var timeRemaining: TimeInterval = 25 * 60
    @Published var currentTrackTitle: String = ""
    @Published var errorMessage: String?
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    @Published var token: String {
        didSet { UserDefaults.standard.set(token, forKey: "plexToken") }
    }
    @Published var isConfigured: Bool = false

    let player = AudioPlayer()
    var client: PlexClient?
    private var timerSubscription: AnyCancellable?
    private var isTimerPaused = false

    init() {
        let savedURL = UserDefaults.standard.string(forKey: "serverURL") ?? "https://your-plex-server:32400"
        let savedToken = UserDefaults.standard.string(forKey: "plexToken") ?? ""
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

    func startPomodoro(seedTrackId: Int?) {
        guard let client = client else {
            errorMessage = "Configure your Plex server first"
            return
        }

        errorMessage = nil
        state = .running

        Task {
            do {
                let seedTrack: PlexTrack
                if let seedTrackId {
                    guard let track = try await client.getTrack(id: seedTrackId) else {
                        throw PlexodoroError.noCurrentTrack
                    }
                    seedTrack = track
                } else {
                    guard let session = try await client.getSessions() else {
                        throw PlexodoroError.noCurrentTrack
                    }
                    seedTrack = session.track
                }
                currentTrackTitle = "\(seedTrack.artist) — \(seedTrack.title)"

                let nearest = try await client.getNearest(trackId: seedTrack.id, limit: PomodoroConfig.default.maxCandidates)
                    .filter { $0.id != seedTrack.id }

                let config = PomodoroConfig.default
                let seedDuration = seedTrack.duration / 1000
                let remainingTarget = config.targetDuration - seedDuration
                let engine = PomodoroEngine()

                let packed = engine.pack(tracks: nearest, target: max(remainingTarget, config.tolerance * 2))
                let playlist = [seedTrack] + packed.shuffled()
                let totalSeconds = engine.totalDuration(of: playlist)

                let urls: [URL] = playlist.compactMap { track in
                    guard !track.key.isEmpty else { return nil }
                    return client.streamURL(for: track)
                }

                guard urls.count == playlist.count else {
                    throw PlexodoroError.noAudioURL
                }

                player.onPlaylistFinished = { [weak self] in
                    Task { @MainActor in
                        self?.timerSubscription?.cancel()
                        self?.state = .finished
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        self?.resetState()
                    }
                }

                player.onStoppedAtTrackEnd = { [weak self] in
                    Task { @MainActor in
                        self?.state = .finished
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        self?.resetState()
                    }
                }

                timeRemaining = totalSeconds
                player.isDownloading = true
                await player.play(tracks: playlist, urls: urls)
                startTimer(duration: totalSeconds)
            } catch {
                errorMessage = error.localizedDescription
                state = .idle
            }
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
        errorMessage = nil
    }

    var formattedTime: String {
        let mins = Int(timeRemaining) / 60
        let secs = Int(timeRemaining) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
