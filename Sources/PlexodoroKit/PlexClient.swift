import Foundation
import Logging

private let log = Logger(label: "com.plexodoro.plexclient")

actor PlexClient: MusicProvider {
    let serverURL: String
    let token: String

    private let decoder = JSONDecoder()
    private let session: URLSession
    private let delegate = CertDelegate()
    private var cachedMusicSectionIDs: [Int]?

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

        let sectionIDs = try await musicSectionIDs()
        let tokens = query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        let searchTerms = tokens.count > 1 ? Array(Set(tokens)) : [query]
        let perSearchLimit = 50

        let batches: [[Track]] = try await withThrowingTaskGroup(of: [Track].self) { group in
            for sectionID in sectionIDs {
                for term in searchTerms {
                    group.addTask { [self] in
                        try await self.searchInSection(sectionID: sectionID, field: "title", value: term, limit: perSearchLimit)
                    }
                    group.addTask { [self] in
                        try await self.searchInSection(sectionID: sectionID, field: "artist.title", value: term, limit: perSearchLimit)
                    }
                }
            }
            var results: [[Track]] = []
            for try await batch in group {
                results.append(batch)
            }
            return results
        }

        var scored: [String: (track: Track, score: Int)] = [:]
        for batch in batches {
            for track in batch {
                if let existing = scored[track.id] {
                    scored[track.id] = (track, existing.score + 1)
                } else {
                    scored[track.id] = (track, 1)
                }
            }
        }

        return scored.values
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.track.title < rhs.track.title
            }
            .prefix(limit)
            .map { $0.track }
    }

    private func musicSectionIDs() async throws -> [Int] {
        if let ids = cachedMusicSectionIDs { return ids }

        let data = try await fetchJSON(path: "/library/sections")
        let container = try decoder.decode(PlexSectionsResponse.self, from: data).mediaContainer
        let ids = container.directories?
            .filter { $0.type == "artist" }
            .compactMap { Int($0.key) } ?? []

        guard !ids.isEmpty else { throw PlexodoroError.serverUnreachable }
        cachedMusicSectionIDs = ids
        return ids
    }

    private func searchInSection(sectionID: Int, field: String, value: String, limit: Int) async throws -> [Track] {
        let data = try await fetchJSON(
            path: "/library/sections/\(sectionID)/all",
            query: [
                URLQueryItem(name: "type", value: "10"),
                URLQueryItem(name: field, value: value),
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
        return tokenURL(path: thumb)
    }

    nonisolated func streamURL(for track: Track) -> URL? {
        guard !track.key.isEmpty else { return nil }
        return tokenURL(path: track.key)
    }

    private nonisolated func tokenURL(path: String) -> URL? {
        guard var components = URLComponents(string: serverURL + path) else { return nil }
        components.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        return components.url
    }
}
