import Foundation

private final class TrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

actor PlexClient {
    let serverURL: String
    let token: String

    private let decoder = JSONDecoder()
    private let session: URLSession
    private let delegate = TrustDelegate()

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
        var req = URLRequest(url: url(path: path, query: query))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpMethod = method
        req.timeoutInterval = 15

        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: req) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data,
                          let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: PlexodoroError.serverUnreachable)
                }
            }.resume()
        }
    }

    func ping() async throws {
        _ = try await fetchJSON(path: "/")
    }

    func searchTracks(query: String, limit: Int = 20) async throws -> [PlexTrack] {
        let data = try await fetchJSON(
            path: "/search",
            query: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "type", value: "10"),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        let container = try decoder.decode(PlexMediaContainer.self, from: data)
        return (container.metadata ?? []).map { $0.toTrack }
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
