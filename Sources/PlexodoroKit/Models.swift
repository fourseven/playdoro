import Foundation

enum UserDefaultsKey {
    static let serverURL = "serverURL"
    static let plexToken = "plexToken"
    static let serverName = "serverName"
    static let plexClientId = "plexClientId"
    static let savedPlaylists = "savedPlaylists"
    static let eqPresetID = "eqPresetID"
    static let eqEnabled = "eqEnabled"
    static let variety = "variety"
}

/// Dedupe by *song* identity (normalized title + artist), not by Plex's
/// rating-key `id`. The same song can surface multiple times from Plex's
/// nearest-neighbour endpoint when it lives on more than one album/library
/// — distinct ids, identical audio. Keying on id left such duplicates in the
/// packed playlist. Title + artist is normalized (lowercased, trimmed) so
/// trivial metadata drift (case, trailing whitespace) doesn't defeat dedup.
func deduplicate(tracks: [Track]) -> [Track] {
    var seen = Set<String>()
    return tracks.filter { seen.insert(songKey(title: $0.title, artist: $0.artist)).inserted }
}

/// Dedupe the candidate pool by song identity, excluding any track that is the
/// same song as a seed. Run this BEFORE packing so the engine fills to the
/// target duration with unique songs — deduping after packing shortens the
/// playlist below target whenever a duplicate gets removed.
func deduplicateForPacking(candidates: [Track], seeds: [Track]) -> [Track] {
    var seen = Set<String>()
    for seed in seeds { seen.insert(songKey(title: seed.title, artist: seed.artist)) }
    return candidates.filter { seen.insert(songKey(title: $0.title, artist: $0.artist)).inserted }
}

func songKey(title: String, artist: String) -> String {
    "\(title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
}

enum PomodoroLimits {
    static let maxSeeds = 4
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

/// Normalize each track's `score` (raw sonic distance from its seed) via
/// min-max within its batch, so the closest track maps to 0 and the farthest
/// to 1. Raw distances are NOT comparable across seeds — a tight cluster
/// (e.g. rap) has uniformly tiny distances while a varied cluster (e.g. pop)
/// has larger ones, so a global ranking would let the tightest cluster
/// dominate. Min-max normalization expresses each track's *relative* position
/// in its own seed's neighbourhood (0 = best match for that seed, 1 = worst),
/// making both the `score` field and the weighted-variety sampling comparable
/// across seeds. Pure helper; batch is assumed to be in nearest-first order.
func normalizeBatchScores(_ batch: [Track]) -> [Track] {
    let distances = batch.compactMap { $0.score }
    guard distances.count >= 2,
          let lo = distances.min(),
          let hi = distances.max(),
          hi > lo else { return batch }
    let range = hi - lo
    return batch.map { track in
        var copy = track
        if let d = copy.score { copy.score = (d - lo) / range }
        return copy
    }
}

/// Interleave nearest-neighbour batches from multiple seeds round-robin
/// (batch0[0], batch1[0], …, batch0[1], batch1[1], …) and dedupe by track id
/// (first occurrence wins). Because each batch is in nearest-first order, this
/// yields rank-0 from every seed, then rank-1 from every seed, etc. — so the
/// packing engine's front-to-back walk rotates across seeds instead of sitting
/// inside whichever single seed has the smallest raw distances. Guarantees
/// balanced cross-seed representation regardless of per-batch sizes.
func interleaveNearestResults(_ batches: [[Track]]) -> [Track] {
    guard !batches.isEmpty else { return [] }
    let maxLen = batches.map(\.count).max() ?? 0
    var seen = Set<String>()
    var out: [Track] = []
    out.reserveCapacity(maxLen * batches.count)
    for index in 0..<maxLen {
        for batch in batches where index < batch.count {
            let track = batch[index]
            if seen.insert(track.id).inserted {
                out.append(track)
            }
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
    var score: Double?
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
    /// Track-selection variety in [0, 1]: 0 = strict (always the sonically
    /// nearest matches), 1 = fully random within each selection window. Drives
    /// weighted sampling in `PomodoroEngine.fillLookahead`.
    var variety: Double = 0.5
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
