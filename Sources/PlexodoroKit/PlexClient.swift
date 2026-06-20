import Foundation
import Logging

private let log = Logger(label: "com.plexodoro.plexclient")

actor PlexClient: MusicProvider {
    let serverURL: String
    let token: String

    private let decoder = JSONDecoder()
    private let session: URLSession
    private let delegate = CertDelegate()

    init(serverURL: String, token: String) {
        self.serverURL = serverURL
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    /// Quick reachability probe with a short timeout. Returns true if the server
    /// responds 2xx to `/`. Uses a throwaway URLSession so it does not interfere
    /// with any real client session. Safe to fire many concurrently.
    static func probe(serverURL: String, token: String, timeout: TimeInterval) async -> Bool {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let probeSession = URLSession(configuration: config, delegate: CertDelegate(), delegateQueue: nil)
        defer { probeSession.finishTasksAndInvalidate() }

        guard let url = URL(string: "\(serverURL)/?X-Plex-Token=\(token)") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Plexodoro", forHTTPHeaderField: "X-Plex-Client-Identifier")

        return await withCheckedContinuation { continuation in
            probeSession.dataTask(with: req) { _, response, _ in
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }.resume()
        }
    }

    func url(path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(string: "\(serverURL)\(path)")!
        var items = query.map { URLQueryItem(name: $0.name, value: percentEncode($0.value ?? "")) }
        items.append(URLQueryItem(name: "X-Plex-Token", value: percentEncode(token)))
        components.percentEncodedQueryItems = items
        return components.url!
    }

    private func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func fetchJSON(path: String, query: [URLQueryItem] = [], method: String = "GET") async throws -> Data {
        let requestURL = url(path: path, query: query)
        log.debug("Request: \(method) \(requestURL.absoluteString)")

        var req = URLRequest(url: requestURL)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Plexodoro", forHTTPHeaderField: "X-Plex-Client-Identifier")
        req.setValue("Plexodoro", forHTTPHeaderField: "X-Plex-Product")
        req.httpMethod = method
        req.timeoutInterval = 15

        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: req) { data, response, error in
                if let error = error {
                    log.error("Network error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else if let data = data,
                          let httpResponse = response as? HTTPURLResponse {
                    let contentType = httpResponse.allHeaderFields["Content-Type"] as? String ?? "none"
                    let bodyPreview = String(data: data.prefix(300), encoding: .utf8) ?? "not utf-8"
                    log.debug("Response: \(httpResponse.statusCode) \(contentType)")
                    log.trace("Body preview: \(bodyPreview)")

                    if (200...299).contains(httpResponse.statusCode) {
                        continuation.resume(returning: data)
                    } else {
                        log.error("Non-2xx status: \(httpResponse.statusCode)")
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
        log.debug("Searching: '\(query)'")
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
