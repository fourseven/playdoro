import Foundation

protocol MusicProvider: Sendable {
    func ping() async throws
    func searchTracks(query: String, limit: Int) async throws -> [Track]
    func getTrack(id: String) async throws -> Track?
    func getNearest(trackId: String, limit: Int) async throws -> [Track]
    func getCurrentTrack() async throws -> Track?
    func streamURL(for track: Track) -> URL?
    func thumbURL(for track: Track) -> URL?
}

extension MusicProvider {
    func searchTracks(query: String) async throws -> [Track] {
        try await searchTracks(query: query, limit: 20)
    }
}
