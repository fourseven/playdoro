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

final class SearchScoringTests: XCTestCase {
    private func make(_ title: String, id: String = "1") -> Track {
        Track(id: id, title: title, artist: "A", album: "B", duration: 0, key: "", thumb: nil, score: nil)
    }

    func testExactTitleMatchScoresHighest() {
        XCTAssertEqual(trackMatchScore(make("stupid song"), query: "stupid song"), 100)
        XCTAssertEqual(trackMatchScore(make("Stupid Song"), query: "stupid song"), 100)
    }

    func testPrefixMatchBeatsSubstring() {
        XCTAssertEqual(trackMatchScore(make("stupid song (demo)"), query: "stupid song"), 60)
    }

    func testSubstringMatchBeatsArtistOnly() {
        XCTAssertEqual(
            trackMatchScore(make("...This Stupid Song Written About Me"), query: "stupid song"),
            30
        )
    }

    func testNonTitleMatchScoresBaseline() {
        XCTAssertEqual(trackMatchScore(make("completely unrelated"), query: "stupid song"), 1)
    }

    func testCurlyApostropheMatchesStraightQuery() {
        XCTAssertEqual(trackMatchScore(make("Don’t Stay"), query: "Don't Stay"), 100)
        XCTAssertEqual(trackMatchScore(make("Don't Stay"), query: "Don’t Stay"), 100)
        XCTAssertEqual(trackMatchScore(make("Don’t Stay Home"), query: "Don't Stay"), 60)
    }

    func testDiacriticsAndPunctuationAreIgnored() {
        XCTAssertEqual(trackMatchScore(make("Ángela"), query: "Angela"), 100)
        XCTAssertEqual(trackMatchScore(make("Run-Away"), query: "Runaway"), 100)
    }

    func testNormalizedTitleOutranksUnrelatedTokenHit() {
        let target = make("Don’t Stay", id: "lp")
        let unrelated = make("Stay", id: "other")
        let scored = scoreSearchBatches([[target, unrelated]], query: "Don't Stay")

        let ranked = scored.values.sorted { $0.score > $1.score }
        XCTAssertEqual(ranked.first?.track.id, "lp", "Normalized exact title match should outrank a plain token hit")
    }

    func testEmptyQueryScoresBaseline() {
        XCTAssertEqual(trackMatchScore(make("anything"), query: "   "), 1)
    }

    func testScoredBatchesRankExactMatchAboveSubstring() {
        // Simulates the bug scenario: an exact "stupid song" track and a
        // substring "...Stupid Song..." track both returned across batches.
        let exact = make("stupid song", id: "olivia")
        let substring = make("I Slept With Someone (Stupid Song)", id: "fob")
        let scored = scoreSearchBatches([[exact, substring], [exact]], query: "stupid song")

        let ranked = scored.values.sorted { $0.score > $1.score }
        XCTAssertEqual(ranked.first?.track.id, "olivia", "Exact title match should outrank a substring match")
        XCTAssertGreaterThan(ranked[0].score, ranked[1].score)
    }
}
