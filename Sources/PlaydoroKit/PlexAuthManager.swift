import Foundation
import Logging
#if canImport(UIKit)
import UIKit
#endif

private let log = Logger(label: AppIdentity.key("plexauth"))

actor PlexAuthManager {
    private let session: URLSession
    private let decoder = JSONDecoder()

    let clientId: String

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)

        if let saved = UserDefaults.standard.string(forKey: UserDefaultsKey.plexClientId) {
            self.clientId = saved
        } else {
            let suffix = UUID().uuidString.prefix(8)
            let id = "playdoro-\(suffix)"
            UserDefaults.standard.set(id, forKey: UserDefaultsKey.plexClientId)
            self.clientId = id
        }
    }

    private var platformName: String {
        #if canImport(UIKit)
        UIDevice.current.model
        #else
        ProcessInfo.processInfo.hostName
        #endif
    }

    private var platformOS: String {
        #if canImport(UIKit)
        "iOS"
        #else
        "macOS"
        #endif
    }

    private var baseHeaders: [String: String] {
        [
            "X-Plex-Client-Identifier": clientId,
            "X-Plex-Product": AppIdentity.name,
            "X-Plex-Device": platformOS,
            "X-Plex-Device-Name": platformName,
            "X-Plex-Platform": platformOS,
            "Accept": "application/json",
        ]
    }

    func requestPin() async throws -> (id: Int, code: String) {
        var req = URLRequest(url: URL(string: "https://plex.tv/api/v2/pins")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in baseHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONEncoder().encode([String: Bool]())

        let data = try await fetch(req)
        let pin = try decoder.decode(PlexPinResponse.self, from: data)
        log.info("Got PIN: \(pin.code)")
        return (pin.id, pin.code)
    }

    func pollForAuth(pinId: Int) async throws -> String {
        var req = URLRequest(url: URL(string: "https://plex.tv/api/v2/pins/\(pinId)")!)
        for (k, v) in baseHeaders { req.setValue(v, forHTTPHeaderField: k) }

        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let data = try await fetch(req)
            let pin = try decoder.decode(PlexPinResponse.self, from: data)
            if let token = pin.authToken, !token.isEmpty {
                log.info("OAuth succeeded, got token")
                return token
            }
            log.trace("Polling… no auth yet")
        }
        throw PlaydoroError.authTimeout
    }

    /// Discover Plex servers and return server name + all connection URIs to try.
    func discoverServers(token: String) async throws -> (serverName: String, uris: [String]) {
        var req = URLRequest(url: URL(string: "https://clients.plex.tv/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1")!)
        for (k, v) in baseHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue(token, forHTTPHeaderField: "X-Plex-Token")

        let data = try await fetch(req)
        log.info("Resources response: \(data.count) bytes")

        let resources: [PlexResource]
        do {
            resources = try decoder.decode([PlexResource].self, from: data)
        } catch {
            let body = String(data: data.prefix(1000), encoding: .utf8) ?? "<non-utf8>"
            log.error("Failed to decode resources: \(error)")
            log.error("Response body: \(body)")
            throw error
        }

        log.info("Found \(resources.count) resources")
        let servers = resources.filter { $0.provides?.contains("server") ?? false }
        log.info("Found \(servers.count) servers")

        guard let server = servers.first(where: { $0.owned ?? false }) ?? servers.first else {
            throw PlaydoroError.noServerFound
        }

        guard let connections = server.connections, !connections.isEmpty else {
            log.warning("Server '\(server.name)' has no connections")
            throw PlaydoroError.noServerFound
        }

        for c in connections {
            log.info("  \(c.uri)  local=\(c.local.map(String.init) ?? "?")")
        }
        let sorted = connections.sorted { a, b in priority(a) > priority(b) }
        let uris = sorted.map(\.uri)
        return (server.name, uris)
    }

    /// Prioritise connections by likelihood of being reachable from this machine.
    private func priority(_ c: PlexResourceConnection) -> Int {
        let host = c.uri.split(separator: "/").dropFirst(2).first.flatMap { String($0).split(separator: ":").first } ?? ""
        if host.hasPrefix("192.168.") || host.hasPrefix("10.") { return 3 }
        if host == "127.0.0.1" || host == "localhost" { return 2 }
        return 0
    }

    private func fetch(_ req: URLRequest) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: req) { data, response, error in
                if let error = error {
                    log.error("Network error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    log.error("No HTTP response")
                    continuation.resume(throwing: PlaydoroError.serverUnreachable)
                    return
                }

                let bodyPreview = data.flatMap { String(data: $0.prefix(500), encoding: .utf8) } ?? "empty"
                log.debug("\(req.httpMethod ?? "GET") \(req.url?.path ?? "?") → \(httpResponse.statusCode)")
                log.trace("Body: \(bodyPreview)")

                guard (200...299).contains(httpResponse.statusCode) else {
                    log.error("Unexpected status: \(httpResponse.statusCode)")
                    continuation.resume(throwing: PlaydoroError.serverUnreachable)
                    return
                }

                if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: PlaydoroError.serverUnreachable)
                }
            }.resume()
        }
    }
}
