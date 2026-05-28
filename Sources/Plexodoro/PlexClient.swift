import Foundation

actor PlexClient {
    let serverURL: String
    let token: String

    private let decoder = JSONDecoder()

    init(serverURL: String, token: String) {
        self.serverURL = serverURL
        self.token = token
    }

    private func url(path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(string: "\(serverURL)\(path)")!
        var items = query
        items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        components.queryItems = items
        return components.url!
    }

    private func fetchJSON(path: String, query: [URLQueryItem] = [], method: String = "GET") async throws -> Data {
        var req = URLRequest(url: url(path: path, query: query))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpMethod = method
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlexodoroError.serverUnreachable
        }
        return data
    }

    func ping() async -> Bool {
        (try? await fetchJSON(path: "/")) != nil
    }

    func getSessions() async throws -> PlexSession? {
        let data = try await fetchJSON(path: "/status/sessions")
        let container = try decoder.decode(PlexMediaContainer.self, from: data)
        guard let track = container.metadata?.first else { return nil }
        return PlexSession(
            track: track.toTrack,
            state: track.player?.state ?? "stopped"
        )
    }

    func getNearest(trackId: Int, limit: Int = 50) async throws -> [PlexTrack] {
        let data = try await fetchJSON(
            path: "/library/metadata/\(trackId)/nearest",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        let container = try decoder.decode(PlexMediaContainer.self, from: data)
        return (container.metadata ?? []).map { $0.toTrack }
    }

    nonisolated func streamURL(for track: PlexTrack) -> URL? {
        guard !track.key.isEmpty else { return nil }
        var components = URLComponents(string: serverURL + track.key)!
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        return components.url
    }
}
