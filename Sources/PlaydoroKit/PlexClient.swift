import Foundation
import Logging
#if canImport(UIKit)
import UIKit
#endif

private let log = Logger(label: AppIdentity.key("plexclient"))

actor PlexClient: MusicCatalog, StreamProviding {
    let serverURL: String
    let token: String
    /// Stable per-install client id, so Plex/Tautulli attribute every session to
    /// the same "Playdoro" client instead of a fresh random one per launch.
    let clientIdentifier: String

    private let decoder = JSONDecoder()
    private let session: URLSession
    private let delegate = CertDelegate()
    private var cachedMusicSectionIDs: [Int]?

    init(serverURL: String, token: String) {
        self.serverURL = serverURL
        self.token = token
        self.clientIdentifier = Self.persistentClientIdentifier()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    private static func persistentClientIdentifier() -> String {
        let key = AppIdentity.key("clientIdentifier")
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = "\(AppIdentity.name)-\(UUID().uuidString)"
        UserDefaults.standard.set(id, forKey: key)
        return id
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
        req.setValue(AppIdentity.name, forHTTPHeaderField: "X-Plex-Client-Identifier")

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

    private func fetchJSON(path: String, query: [URLQueryItem] = [], method: String = "GET", headers: [String: String] = [:]) async throws -> Data {
        let requestURL = url(path: path, query: query)
        log.debug("Request: \(method) \(requestURL.absoluteString)")

        var req = URLRequest(url: requestURL)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(self.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        req.setValue(AppIdentity.name, forHTTPHeaderField: "X-Plex-Product")
        for (field, value) in headers {
            req.setValue(value, forHTTPHeaderField: field)
        }
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
                        continuation.resume(throwing: PlaydoroError.serverUnreachable)
                    }
                } else {
                    log.error("No data or response")
                    continuation.resume(throwing: PlaydoroError.serverUnreachable)
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
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        log.debug("Searching: '\(trimmed)'")

        let sectionIDs = try await musicSectionIDs()

        // Primary: full-phrase search. Plex matches the whole query as a
        // (case-insensitive) substring, so "stupid song" hits the literal title
        // rather than every track containing the word "song". The global
        // /search endpoint also covers artist/album matches with Plex's own
        // relevance ranking.
        let phraseBatches = try await runFieldSearches(
            terms: [trimmed],
            sectionIDs: sectionIDs,
            includeGlobal: true,
            perSearchLimit: 50
        )
        var scored = scoreSearchBatches(phraseBatches, query: trimmed)

        // Fallback: a reordered/partial query (e.g. "song stupid") won't match
        // as a phrase, so fall back to per-token field searches so partial
        // matches still surface. Plex truncates token matches by its own
        // relevance, so pull a wide window and re-rank with normalization.
        if scored.isEmpty {
            let tokens = Array(Set(trimmed.split(separator: " ").map(String.init)))
            let tokenBatches = try await runFieldSearches(
                terms: tokens,
                sectionIDs: sectionIDs,
                includeGlobal: false,
                perSearchLimit: 500
            )
            scored = scoreSearchBatches(tokenBatches, query: trimmed)
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

        guard !ids.isEmpty else { throw PlaydoroError.serverUnreachable }
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

    /// Runs `title` + `artist.title` field searches for every (term × section),
    /// plus one global full-text `/search` per term when `includeGlobal` is set.
    /// All requests fire concurrently; results come back as raw per-query batches.
    private func runFieldSearches(
        terms: [String],
        sectionIDs: [Int],
        includeGlobal: Bool,
        perSearchLimit: Int
    ) async throws -> [[Track]] {
        try await withThrowingTaskGroup(of: [Track].self) { group in
            if includeGlobal {
                for term in terms {
                    group.addTask { [self] in
                        try await self.globalSearch(query: term, limit: perSearchLimit)
                    }
                }
            }
            for sectionID in sectionIDs {
                for term in terms {
                    group.addTask { [self] in
                        try await self.searchInSection(sectionID: sectionID, field: "title", value: term, limit: perSearchLimit)
                    }
                    group.addTask { [self] in
                        try await self.searchInSection(sectionID: sectionID, field: "artist.title", value: term, limit: perSearchLimit)
                    }
                }
            }
            var results: [[Track]] = []
            for try await batch in group { results.append(batch) }
            return results
        }
    }

    /// Plex's library-wide full-text search (`/search?query=`). Searches across
    /// title/artist/album with Plex's own relevance ranking. Filtered to tracks
    /// only, since the endpoint returns every metadata type (movies, shows, …).
    private func globalSearch(query: String, limit: Int) async throws -> [Track] {
        let data = try await fetchJSON(
            path: "/search",
            query: [
                URLQueryItem(name: "type", value: "10"),
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        let container = try decodeContainer(from: data)
        return (container.metadata ?? [])
            .filter { $0.type == "track" }
            .map { $0.toTrack }
    }

    func getNearest(trackId: String, limit: Int = 50) async throws -> [Track] {
        let data = try await fetchJSON(
            path: "/library/metadata/\(trackId)/nearest",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        let container = try decodeContainer(from: data)
        return (container.metadata ?? []).map { $0.toTrack }
    }

    /// Report a live playback session for `track` to Plex's timeline API.
    /// `state = .playing` creates/advances a session that appears in Tautulli
    /// and Plex Web under the Playdoro client; `.stopped` at full duration
    /// ends it and marks the item watched. Sent by AppState on state changes
    /// and on a slow cadence while playing.
    func reportPlayback(for track: Track, time: TimeInterval, duration: TimeInterval, state: PlaybackState) async throws {
        let ms = Int(time * 1000)
        let durationMs = Int(duration * 1000)
        let headers = [
            "X-Plex-Platform": platformName,
            "X-Plex-Platform-Version": Self.platformVersion,
            "X-Plex-Version": AppIdentity.version,
            "X-Plex-Device": AppIdentity.name,
            "X-Plex-Device-Name": AppIdentity.name,
            "X-Plex-Model": AppIdentity.name,
            "X-Plex-Product": AppIdentity.name,
        ]
        _ = try await fetchJSON(
            path: "/:/timeline",
            query: [
                URLQueryItem(name: "ratingKey", value: track.id),
                URLQueryItem(name: "key", value: "/library/metadata/\(track.id)"),
                URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
                URLQueryItem(name: "state", value: state.rawValue),
                URLQueryItem(name: "time", value: String(ms)),
                URLQueryItem(name: "duration", value: String(durationMs)),
            ],
            headers: headers
        )
        log.info("Timeline \(state.rawValue) \(track.title) [#\(track.id)] at \(ms)ms/\(durationMs)ms")
    }

    private var platformName: String {
        #if canImport(UIKit)
        return "iOS"
        #else
        return "macOS"
        #endif
    }

    private static var platformVersion: String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
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
