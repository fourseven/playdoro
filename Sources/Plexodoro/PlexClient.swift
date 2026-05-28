import Foundation
import OSLog

private let log = Logger(subsystem: "com.mathewhartley.plexodoro", category: "PlexClient")

actor PlexClient {
    let serverURL: String
    let token: String

    private let decoder = JSONDecoder()
    private let session: URLSession
    private let delegate = CertDelegate()

    init(serverURL: String, token: String) {
        self.serverURL = serverURL
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    private func url(path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(string: "\(serverURL)\(path)")!
        var items = query
        items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        components.queryItems = items
        return components.url!
    }

    private func fetchJSON(path: String, query: [URLQueryItem] = [], method: String = "GET") async throws -> Data {
        let requestURL = url(path: path, query: query)
        log.debug("Request: \(method) \(requestURL.absoluteString, privacy: .public)")

        var req = URLRequest(url: requestURL)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Plexodoro", forHTTPHeaderField: "X-Plex-Client-Identifier")
        req.setValue("Plexodoro", forHTTPHeaderField: "X-Plex-Product")
        req.httpMethod = method
        req.timeoutInterval = 15

        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: req) { data, response, error in
                if let error = error {
                    log.error("Network error: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                } else if let data = data,
                          let httpResponse = response as? HTTPURLResponse {
                    let contentType = httpResponse.allHeaderFields["Content-Type"] as? String ?? "none"
                    let bodyPreview = String(data: data.prefix(300), encoding: .utf8) ?? "not utf-8"
                    log.debug("Response: \(httpResponse.statusCode) \(contentType, privacy: .public)")
                    log.debug("Body preview: \(bodyPreview, privacy: .public)")

                    if httpResponse.statusCode == 200 {
                        continuation.resume(returning: data)
                    } else {
                        log.error("Non-200 status: \(httpResponse.statusCode)")
                        continuation.resume(throwing: PlexodoroError.serverUnreachable)
                    }
                } else {
                    log.error("No data or response")
                    continuation.resume(throwing: PlexodoroError.serverUnreachable)
                }
            }.resume()
        }
    }

    func ping() async throws {
        _ = try await fetchJSON(path: "/")
    }

    private func decodeContainer(from data: Data) throws -> PlexMediaContainer {
        try decoder.decode(PlexResponse.self, from: data).mediaContainer
    }

    func getTrack(id: String) async throws -> Track? {
        let data = try await fetchJSON(path: "/library/metadata/\(id)")
        let container = try decodeContainer(from: data)
        return container.metadata?.first?.toTrack
    }

    func searchTracks(query: String, limit: Int = 20) async throws -> [Track] {
        log.debug("Searching: '\(query, privacy: .public)'")
        let data = try await fetchJSON(
            path: "/search",
            query: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "type", value: "10"),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        let container = try decodeContainer(from: data)
        return (container.metadata ?? []).map { $0.toTrack }
    }

    func getSessions() async throws -> PlexSession? {
        let data = try await fetchJSON(path: "/status/sessions")
        let container = try decodeContainer(from: data)
        guard let track = container.metadata?.first else { return nil }
        return PlexSession(
            track: track.toTrack,
            state: track.player?.state ?? "stopped"
        )
    }

    func getNearest(trackId: String, limit: Int = 50) async throws -> [Track] {
        let data = try await fetchJSON(
            path: "/library/metadata/\(trackId)/nearest",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        let container = try decodeContainer(from: data)
        return (container.metadata ?? []).map { $0.toTrack }
    }

    nonisolated func thumbURL(for track: Track) -> URL? {
        guard let thumb = track.thumb else { return nil }
        let item = URLQueryItem(name: "X-Plex-Token", value: token)
        var components = URLComponents(string: serverURL + thumb)!
        components.queryItems = [item]
        return components.url
    }

    nonisolated func streamURL(for track: Track) -> URL? {
        guard !track.key.isEmpty else { return nil }
        let item = URLQueryItem(name: "X-Plex-Token", value: token)
        var components = URLComponents(string: serverURL + track.key)!
        components.queryItems = [item]
        return components.url
    }
}
