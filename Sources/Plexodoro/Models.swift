import Foundation

enum UserDefaultsKey {
    static let serverURL = "serverURL"
    static let plexToken = "plexToken"
}

func deduplicate(tracks: [Track]) -> [Track] {
    var seen = Set<String>()
    return tracks.filter { seen.insert("\($0.id)-\($0.title)-\($0.artist)").inserted }
}

struct Track: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let key: String
    let thumb: String?
    let score: Double?
}

struct PlexSession {
    let track: Track
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
    var maxCandidates: Int = 200
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
    let librarySectionID: Int?
    let media: [PlexMediaJSON]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, title, grandparentTitle, parentTitle, duration
        case thumb, distance, type, player, librarySectionID
        case media = "Media"
    }

    var toTrack: Track {
        Track(
            id: ratingKey,
            title: title ?? "Unknown",
            artist: grandparentTitle ?? "Unknown",
            album: parentTitle ?? "Unknown",
            duration: TimeInterval(duration ?? 0),
            key: media?.first?.part?.first?.key ?? "",
            thumb: thumb,
            score: distance
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
