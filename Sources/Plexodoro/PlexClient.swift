import Foundation

actor PlexClient {
    let serverURL: String
    let token: String
    var playerURL: String?

    private let decoder = JSONDecoder()

    init(serverURL: String, token: String) {
        self.serverURL = serverURL
        self.token = token
    }

    private func serverURL(path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(string: "\(serverURL)\(path)")!
        var items = query
        items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        components.queryItems = items
        return components.url!
    }

    private func fetchServerJSON(path: String, query: [URLQueryItem] = [], method: String = "GET") async throws -> Data {
        var req = URLRequest(url: serverURL(path: path, query: query))
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

    private func sendToPlayer(path: String, query: [URLQueryItem] = []) async throws {
        guard let base = playerURL else {
            throw PlexodoroError.noAvailablePlayer
        }

        var components = URLComponents(string: "\(base)\(path)")!
        var items = query
        items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        components.queryItems = items

        var req = URLRequest(url: components.url!)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Plexodoro", forHTTPHeaderField: "X-Plex-Client-Identifier")
        req.setValue("Plexodoro", forHTTPHeaderField: "X-Plex-Product")
        req.setValue("1.0", forHTTPHeaderField: "X-Plex-Version")
        req.setValue("macOS", forHTTPHeaderField: "X-Plex-Platform")
        req.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PlexodoroError.playbackFailed
        }
    }
}

// MARK: - Data Endpoints (to Plex Server)

extension PlexClient {
    func getSessions() async throws -> PlexSession? {
        let data = try await fetchServerJSON(path: "/status/sessions")
        let container = try decoder.decode(PlexMediaContainer.self, from: data)
        guard let track = container.metadata?.first else { return nil }
        return PlexSession(
            track: track.toTrack,
            state: track.player?.state ?? "stopped"
        )
    }

    func getNearest(trackId: Int, limit: Int = 50) async throws -> [PlexTrack] {
        let data = try await fetchServerJSON(
            path: "/library/metadata/\(trackId)/nearest",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        let container = try decoder.decode(PlexMediaContainer.self, from: data)
        return (container.metadata ?? []).map { $0.toTrack }
    }

    func getClients() async throws -> [PlexClientInfo] {
        let data = try await fetchServerJSON(path: "/clients")
        let container = try decoder.decode(PlexMediaContainer.self, from: data)
        let clients = (container.server ?? []).map { $0.toClient }

        // Cache the first PlexAmp player URL
        if let plexAmp = clients.first(where: { $0.product == "Plexamp" }) {
            playerURL = "http://\(plexAmp.host):\(plexAmp.port)"
        }

        return clients
    }

    func createPlaylist(title: String, trackIds: [Int]) async throws -> String {
        let ids = trackIds.map(String.init).joined(separator: ",")
        let machineId = "fc3099306e906d1526108cb0d28e968d2e046342"
        let data = try await fetchServerJSON(
            path: "/playlists",
            query: [
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "type", value: "audio"),
                URLQueryItem(name: "smart", value: "0"),
                URLQueryItem(name: "uri", value: "server://\(machineId)/com.plexapp.plugins.library/library/metadata/\(ids)"),
            ],
            method: "POST"
        )
        let container = try decoder.decode(PlexMediaContainer.self, from: data)
        if let key = container.metadata?.first?.ratingKey {
            return "/playlists/\(key)"
        }
        return title
    }

    func deletePlaylist(playlistKey: String) async throws {
        let id = playlistKey.dropPrefix("/playlists/")
        _ = try await fetchServerJSON(
            path: "/playlists/\(id)",
            method: "DELETE"
        )
    }
}

// MARK: - Playback Commands (to Player)

extension PlexClient {
    func playPlaylist(clientId: String, playlistKey: String) async throws {
        try await sendToPlayer(
            path: "/player/playback/playMedia",
            query: [
                URLQueryItem(name: "machineIdentifier", value: clientId),
                URLQueryItem(name: "key", value: playlistKey),
            ]
        )
    }

    func stopPlayback(clientId: String) async throws {
        try await sendToPlayer(
            path: "/player/playback/stop",
            query: [
                URLQueryItem(name: "machineIdentifier", value: clientId),
            ]
        )
    }
}

extension String {
    func dropPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
