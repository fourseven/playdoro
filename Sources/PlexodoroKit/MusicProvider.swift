import Foundation

/// Playback lifecycle state reported to the provider's session timeline.
/// `stopped` at full duration is what tells servers like Plex the item was
/// watched.
enum PlaybackState: String {
    case playing
    case paused
    case stopped
}

protocol MusicProvider: Sendable {
    func ping() async throws
    func searchTracks(query: String, limit: Int) async throws -> [Track]
    func getTrack(id: String) async throws -> Track?
    func getNearest(trackId: String, limit: Int) async throws -> [Track]
    func streamURL(for track: Track) -> URL?
    func thumbURL(for track: Track) -> URL?
    /// Report a live playback position/state for `track` so the provider's
    /// sessions and history reflect real playback (visible in Tautulli / Plex
    /// Web). `time` and `duration` are in seconds.
    func reportPlayback(for track: Track, time: TimeInterval, duration: TimeInterval, state: PlaybackState) async throws
}

extension MusicProvider {
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
}
