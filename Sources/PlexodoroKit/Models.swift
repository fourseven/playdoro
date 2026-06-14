import Foundation

enum UserDefaultsKey {
    static let serverURL = "serverURL"
    static let plexToken = "plexToken"
    static let serverName = "serverName"
    static let plexClientId = "plexClientId"
}

func deduplicate(tracks: [Track]) -> [Track] {
    var seen = Set<String>()
    return tracks.filter { seen.insert("\($0.id)-\($0.title)-\($0.artist)").inserted }
}

enum PomodoroLimits {
    static let maxSeeds = 3
}

/// Merge nearest-neighbour batches from multiple seeds, preserving first-occurrence order
/// and deduping by track id.
func mergeNearestResults(_ batches: [[Track]]) -> [Track] {
    var seen = Set<String>()
    var out: [Track] = []
    for batch in batches {
        for track in batch where seen.insert(track.id).inserted {
            out.append(track)
        }
    }
    return out
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
    var isDownloaded = false
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
    case authTimeout
    case noServerFound
    case authCancelled

    var errorDescription: String? {
        switch self {
        case .serverUnreachable: "Cannot reach Plex server"
        case .noCurrentTrack: "No track is currently playing"
        case .noSonicAnalysis: "Sonic analysis is not enabled on your library"
        case .noAudioURL: "Could not get audio stream URL for tracks"
        case .playbackFailed: "Failed to start audio playback"
        case .authTimeout: "Authorization timed out. Please try again."
        case .noServerFound: "No Plex server found on your network"
        case .authCancelled: "Authorization cancelled"
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

// MARK: - OAuth Models

struct PlexPinResponse: Decodable {
    let id: Int
    let code: String
    let trusted: Bool
    let clientIdentifier: String
    let product: String
    let qr: String?
    let authToken: String?
    let expiresAt: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, code, trusted, qr, product
        case clientIdentifier = "clientIdentifier"
        case authToken = "authToken"
        case expiresAt = "expiresAt"
        case createdAt = "createdAt"
    }
}

struct PlexResource: Decodable {
    let name: String
    let product: String?
    let provides: String?
    let owned: Bool?
    let accessToken: String?
    let connections: [PlexResourceConnection]?
    let lastSeenAt: String?
}

struct PlexResourceConnection: Decodable {
    let uri: String
    let local: Bool?
    let address: String?
    let port: Int?
    let status: Int?
    let message: String?
}
