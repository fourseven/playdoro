import Foundation

/// Playback lifecycle state reported to a provider's session timeline.
/// `stopped` at full duration is what tells servers like Plex the item was
/// watched.
enum PlaybackState: String, Sendable {
    case playing
    case paused
    case stopped
}

/// Catalog operations for a music provider: reachability, search, identity,
/// similarity ranking, and artwork. Playback is deliberately NOT part of this
/// protocol — how audio is delivered differs wildly between providers, so that
/// lives in `PlaybackBackend`.
protocol MusicCatalog: Sendable {
    func ping() async throws
    func searchTracks(query: String, limit: Int) async throws -> [Track]
    func getTrack(id: String) async throws -> Track?
    /// Tracks ranked by similarity to a seed track (`score` in models is 0 =
    /// closest). Plex supplies real scores from its nearest-neighbour hub;
    /// providers without one synthesize rank-based pseudo-scores.
    func getNearest(trackId: String, limit: Int) async throws -> [Track]
    func thumbURL(for track: Track) -> URL?
    /// Report a live playback position/state for `track` so the provider's
    /// sessions and history reflect real playback. `time` and `duration` are
    /// in seconds. Default is a no-op — only providers with a writable session
    /// timeline (Plex) override this; others already track listening.
    func reportPlayback(for track: Track, time: TimeInterval, duration: TimeInterval, state: PlaybackState) async throws
}

extension MusicCatalog {
    func searchTracks(query: String) async throws -> [Track] {
        try await searchTracks(query: query, limit: 20)
    }

    func getNearest(trackIds: [String], limit: Int) async throws -> [Track] {
        guard !trackIds.isEmpty else { return [] }
        let perId = max(1, limit / trackIds.count)

        return try await withThrowingTaskGroup(of: (Int, [Track]).self) { group in
            for (index, id) in trackIds.enumerated() {
                group.addTask { [self] in
                    let batch = try await self.getNearest(trackId: id, limit: perId)
                    return (index, normalizeBatchScores(batch))
                }
            }
            var indexed: [(Int, [Track])] = []
            for try await item in group { indexed.append(item) }
            indexed.sort { $0.0 < $1.0 }
            return interleaveNearestResults(indexed.map { $0.1 })
        }
    }

    func reportPlayback(for track: Track, time: TimeInterval, duration: TimeInterval, state: PlaybackState) async throws {}
}

/// Providers that hand out directly playable stream URLs (Plex). This is the
/// only delivery model that feeds the engine backend — other providers play
/// through their own player and implement `PlaybackBackend` directly.
protocol StreamProviding: Sendable {
    func streamURL(for track: Track) -> URL?
}