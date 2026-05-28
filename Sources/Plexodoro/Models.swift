import Foundation

struct PlexTrack: Identifiable, Equatable {
    let id: Int
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let thumb: String?
    let distance: Double?
}

struct PlexClientInfo: Identifiable {
    let id: String
    let name: String
    let host: String
    let port: Int
    let product: String
    let deviceClass: String
}

struct PlexSession {
    let track: PlexTrack
    let state: String
}

enum PomodoroState: Equatable {
    case idle
    case running
    case stopping
    case finished
}

struct PomodoroConfig {
    var targetDuration: TimeInterval = 25 * 60
    var tolerance: TimeInterval = 60
    var maxCandidates: Int = 50
    static let `default` = PomodoroConfig()
}

enum PlexodoroError: LocalizedError {
    case serverUnreachable
    case noCurrentTrack
    case noSonicAnalysis
    case noAvailablePlayer
    case playlistCreationFailed
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .serverUnreachable: "Cannot reach Plex server"
        case .noCurrentTrack: "No track is currently playing"
        case .noSonicAnalysis: "Sonic analysis is not enabled on your library"
        case .noAvailablePlayer: "No PlexAmp or Plex player found"
        case .playlistCreationFailed: "Failed to create pomodoro playlist"
        case .playbackFailed: "Failed to start playback"
        }
    }
}

// MARK: - JSON Response Models

struct PlexMediaContainer: Decodable {
    let size: Int?
    let metadata: [PlexTrackJSON]?
    let server: [PlexServerJSON]?

    enum CodingKeys: String, CodingKey {
        case size
        case metadata = "Metadata"
        case server = "Server"
    }
}

struct PlexTrackJSON: Decodable {
    let ratingKey: String
    let title: String?
    let grandparentTitle: String?
    let parentTitle: String?
    let duration: Int?
    let thumb: String?
    let distance: Double?
    let type: String?
    let player: PlexPlayerJSON?
    let librarySectionID: String?

    var toTrack: PlexTrack {
        PlexTrack(
            id: Int(ratingKey) ?? 0,
            title: title ?? "Unknown",
            artist: grandparentTitle ?? "Unknown",
            album: parentTitle ?? "Unknown",
            duration: TimeInterval(duration ?? 0),
            thumb: thumb,
            distance: distance
        )
    }
}

struct PlexPlayerJSON: Decodable {
    let state: String
}

struct PlexServerJSON: Decodable {
    let name: String
    let host: String
    let port: Int
    let machineIdentifier: String
    let product: String
    let deviceClass: String

    var toClient: PlexClientInfo {
        PlexClientInfo(
            id: machineIdentifier,
            name: name,
            host: host,
            port: port,
            product: product,
            deviceClass: deviceClass
        )
    }
}
