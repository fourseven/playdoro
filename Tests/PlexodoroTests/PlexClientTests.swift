import XCTest
import Foundation
@testable import PlexodoroKit

final class PlexClientTests: XCTestCase {
    func testSearchURLPercentEncodesPlusSign() async throws {
        let client = PlexClient(serverURL: "http://localhost:32400", token: "abc123")
        let url = await client.url(
            path: "/search",
            query: [
                URLQueryItem(name: "query", value: "u + me = <3"),
                URLQueryItem(name: "type", value: "10"),
                URLQueryItem(name: "limit", value: "20")
            ]
        )

        let absolute = url.absoluteString
        XCTAssertTrue(absolute.contains("query=u%20%2B%20me%20%3D%20%3C3"), "Expected '+' to be encoded as %2B in: \(absolute)")
        XCTAssertTrue(absolute.contains("X-Plex-Token=abc123"), "Expected token in: \(absolute)")
    }

    func testSearchURLPercentEncodesAmpersandAndEquals() async throws {
        let client = PlexClient(serverURL: "http://localhost:32400", token: "tok=en")
        let url = await client.url(
            path: "/search",
            query: [URLQueryItem(name: "query", value: "A&B=C")]
        )

        let absolute = url.absoluteString
        XCTAssertTrue(absolute.contains("query=A%26B%3DC"), "Expected '&' and '=' to be encoded in: \(absolute)")
        XCTAssertTrue(absolute.contains("X-Plex-Token=tok%3Den"), "Expected '=' in token to be encoded in: \(absolute)")
    }
}
