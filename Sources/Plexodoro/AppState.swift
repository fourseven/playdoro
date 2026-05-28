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

    private var client: PlexClient?
    private var timerSubscription: AnyCancellable?

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
                let _ = try await client?.getClients()
                isConfigured = true
                errorMessage = nil
            } catch {
                isConfigured = false
                errorMessage = "Could not connect to Plex server"
            }
        }
    }

    func startPomodoro() {
        guard let client = client else {
            errorMessage = "Configure your Plex server first"
            return
        }

        errorMessage = nil
        state = .running

        Task {
            do {
                guard let session = try await client.getSessions() else {
                    throw PlexodoroError.noCurrentTrack
                }

                currentTrackTitle = "\(session.track.artist) — \(session.track.title)"

                let nearest = try await client.getNearest(trackId: session.track.id)
                let engine = PomodoroEngine()
                let packed = engine.pack(tracks: nearest)
                let totalSeconds = engine.totalDuration(of: packed)

                let playlistId = try await client.createPlaylist(
                    title: "Plexodoro - \(Date.now.formatted(date: .omitted, time: .shortened))",
                    trackIds: packed.map { $0.id }
                )

                let plexAmpClients = try await client.getClients()
                guard let player = plexAmpClients.first else {
                    throw PlexodoroError.noAvailablePlayer
                }

                try await client.playPlaylist(
                    clientId: player.id,
                    playlistKey: "/playlists/\(playlistId)"
                )

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

        Task {
            if let client = client {
                let clients = try? await client.getClients()
                if let player = clients?.first {
                    try? await client.stopPlayback(clientId: player.id)
                }
            }
            resetState()
        }
    }

    private func startTimer(duration: TimeInterval) {
        timeRemaining = duration
        timerSubscription = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.state == .running else { return }
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

        Task {
            if let client = client {
                let clients = try? await client.getClients()
                if let player = clients?.first {
                    try? await client.stopPlayback(clientId: player.id)
                }
            }
            state = .finished
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            resetState()
        }
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
