import Foundation

protocol MusicProvider: Sendable {
    func ping() async throws
    func searchTracks(query: String, limit: Int) async throws -> [Track]
    func getTrack(id: String) async throws -> Track?
    func getNearest(trackId: String, limit: Int) async throws -> [Track]
    func streamURL(for track: Track) -> URL?
    func thumbURL(for track: Track) -> URL?
}

extension MusicProvider {
    func searchTracks(query: String) async throws -> [Track] {
        try await searchTracks(query: query, limit: 20)
    }

    func getNearest(trackIds: [String], limit: Int) async throws -> [Track] {
        guard !trackIds.isEmpty else { return [] }
        let perId = max(1, limit / trackIds.count)

        return try await withThrowingTaskGroup(of: [Track].self) { group in
            for id in trackIds {
                group.addTask { [self] in
                    try await self.getNearest(trackId: id, limit: perId)
                }
            }
            var batches: [[Track]] = []
            for try await batch in group {
                batches.append(batch)
            }
            return mergeNearestResults(batches)
        }
    }
}
