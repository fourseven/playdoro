import Foundation

enum UserDefaultsKey {
    static let serverURL = "serverURL"
    static let plexToken = "plexToken"
    static let serverName = "serverName"
    static let plexClientId = "plexClientId"
    static let savedPlaylists = "savedPlaylists"
    static let eqPresetID = "eqPresetID"
    static let eqEnabled = "eqEnabled"
}

func deduplicate(tracks: [Track]) -> [Track] {
    var seen = Set<String>()
    return tracks.filter { seen.insert("\($0.id)-\($0.title)-\($0.artist)").inserted }
}

enum PomodoroLimits {
    static let maxSeeds = 3
    static let savedPlaylistsMax = 3
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

/// Relevance weight for a single search hit. Used by `PlexClient.searchTracks`
/// to rank results: an exact (case-insensitive) title match beats a prefix
/// match, which beats a substring match, which beats an artist/album-only hit.
/// Pure so it can be unit-tested without hitting the network.
func trackMatchScore(_ track: Track, query: String) -> Int {
    let q = query.lowercased().trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return 1 }
    let title = track.title.lowercased()
    if title == q { return 100 }
    if title.hasPrefix(q) { return 60 }
    if title.contains(q) { return 30 }
    return 1
}

/// Score and merge raw search batches into an id-keyed map, summing each
/// track's relevance weight across every batch it appears in. Pure helper for
/// `PlexClient.searchTracks`.
func scoreSearchBatches(_ batches: [[Track]], query: String) -> [String: (track: Track, score: Int)] {
    var scored: [String: (track: Track, score: Int)] = [:]
    for batch in batches {
        for track in batch {
            let weight = trackMatchScore(track, query: query)
            if let existing = scored[track.id] {
                scored[track.id] = (track, existing.score + weight)
            } else {
                scored[track.id] = (track, weight)
            }
        }
    }
    return scored
}

struct Track: Identifiable, Equatable, Codable {
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

struct SeedPlaylist: Codable, Identifiable, Equatable {
    let id: UUID
    let savedAt: Date
    let seeds: [Track]

    init(id: UUID = UUID(), savedAt: Date = Date(), seeds: [Track]) {
        self.id = id
        self.savedAt = savedAt
        self.seeds = seeds
    }

    /// Stable signature for dedup: order-insensitive set of seed ids.
    var signature: [String] { seeds.map(\.id).sorted() }
}

/// Pure helper: prepend a freshly-played playlist to the saved list, deduping by
/// seed-id signature, then cap at `maxRetained` (oldest dropped). Used by AppState
/// after a successful pomodoro start.
func mergeSavedPlaylists(existing: [SeedPlaylist], added: SeedPlaylist, maxRetained: Int) -> [SeedPlaylist] {
    let addedSig = added.signature
    let filtered = existing.filter { $0.signature != addedSig }
    return ([added] + filtered).prefix(maxRetained).map { $0 }
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
    case trackUnavailable
    case noSonicAnalysis
    case noAudioURL
    case playbackFailed
    case authTimeout
    case noServerFound
    case authCancelled

    var errorDescription: String? {
        switch self {
        case .serverUnreachable: "Cannot reach Plex server"
        case .trackUnavailable: "Could not load one of the selected tracks"
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
    let librarySectionID: Int?
    let media: [PlexMediaJSON]?

    enum CodingKeys: String, CodingKey {
        case ratingKey, title, grandparentTitle, parentTitle, duration
        case thumb, distance, type, librarySectionID
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

// MARK: - Library Sections Models

struct PlexSectionsResponse: Decodable {
    let mediaContainer: PlexSectionsContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

struct PlexSectionsContainer: Decodable {
    let directories: [PlexSection]?

    enum CodingKeys: String, CodingKey {
        case directories = "Directory"
    }
}

struct PlexSection: Decodable {
    let key: String
    let type: String?
    let title: String?
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
