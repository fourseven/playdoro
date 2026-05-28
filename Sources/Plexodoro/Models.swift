import Foundation

struct PlexTrack: Identifiable, Equatable {
    let id: Int
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let key: String
    let thumb: String?
    let distance: Double?
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
    case noAudioURL
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .serverUnreachable: "Cannot reach Plex server"
        case .noCurrentTrack: "No track is currently playing"
        case .noSonicAnalysis: "Sonic analysis is not enabled on your library"
        case .noAudioURL: "Could not get audio stream URL for tracks"
        case .playbackFailed: "Failed to start audio playback"
        }
    }
}

// MARK: - JSON Response Models

struct PlexResponse: Decodable {
    let mediaContainer: PlexMediaContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexMediaContainer: Decodable {
    let size: Int?
    let metadata: [PlexTrackJSON]?

    enum CodingKeys: String, CodingKey {
        case size
        case metadata = "Metadata"
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
    let media: [PlexMediaJSON]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, title, grandparentTitle, parentTitle, duration
        case thumb, distance, type, player, librarySectionID
        case media = "Media"
    }

    var toTrack: PlexTrack {
        PlexTrack(
            id: Int(ratingKey) ?? 0,
            title: title ?? "Unknown",
            artist: grandparentTitle ?? "Unknown",
            album: parentTitle ?? "Unknown",
            duration: TimeInterval(duration ?? 0),
            key: media?.first?.part?.first?.key ?? "",
            thumb: thumb,
            distance: distance
        )
    }
}

struct PlexMediaJSON: Decodable {
    let part: [PlexPartJSON]?

    enum CodingKeys: String, CodingKey {
        case part = "Part"
    }
}

struct PlexPartJSON: Decodable {
    let key: String?
}

struct PlexPlayerJSON: Decodable {
    let state: String
}
