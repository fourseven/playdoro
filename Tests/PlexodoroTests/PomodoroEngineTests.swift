import XCTest
import Foundation
@testable import Plexodoro

final class PomodoroEngineTests: XCTestCase {
    // MARK: - Helpers

    func makeTrack(id: Int, duration: TimeInterval, distance: Double = 1.0) -> Track {
        Track(
            id: String(id),
            title: "Track \(id)",
            artist: "Artist",
            album: "Album",
            duration: duration * 1000,
            key: "",
            thumb: nil,
            score: distance
        )
    }

    // MARK: - Happy Path

    func testPacksTracksWithinTargetRange() {
        // 10 small tracks so any random selection reaches minDuration
        let tracks = (1...10).map { makeTrack(id: $0, duration: 60, distance: Double($0) * 0.1) }

        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 300,
            tolerance: 60,
            maxCandidates: 50
        ))

        let result = engine.pack(tracks: tracks, target: 300)
        let total = engine.totalDuration(of: result)

        // Phase 1 picks at most one track per lookahead-of-3 group (guaranteed >= 4 tracks).
        // Greedy fallback fills remaining capacity.
        XCTAssertGreaterThanOrEqual(total, 240)
        XCTAssertLessThanOrEqual(total, 360)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Edge Cases

    func testFiltersTracksExceedingMaxDuration() {
        let tracks = [
            makeTrack(id: 1, duration: 300, distance: 0.1),
            makeTrack(id: 2, duration: 700, distance: 0.2),
        ]

        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 560,
            tolerance: 60,
            maxCandidates: 50
        ))

        let result = engine.pack(tracks: tracks, target: 560)

        // Track 2 (700s) exceeds maxDuration (620) so only track 1 fits
        XCTAssertFalse(result.contains(where: { $0.id == "2" }))
        XCTAssertEqual(result.count, 1)
    }

    func testRespectsMaxDuration() {
        let tracks = [
            makeTrack(id: 1, duration: 300, distance: 0.1),
            makeTrack(id: 2, duration: 400, distance: 0.2),
        ]

        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 350,
            tolerance: 60,
            maxCandidates: 50
        ))

        let result = engine.pack(tracks: tracks, target: 350)
        let total = engine.totalDuration(of: result)

        XCTAssertLessThanOrEqual(total, 410)
    }

    func testReturnsSingleTrackIfUnderMin() {
        let track = makeTrack(id: 1, duration: 300, distance: 0.1)
        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 500,
            tolerance: 60,
            maxCandidates: 50
        ))
        let result = engine.pack(tracks: [track], target: 500)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "1")
    }

    func testEmptyTracksReturnsEmpty() {
        let engine = PomodoroEngine()
        let result = engine.pack(tracks: [], target: 300)
        XCTAssertTrue(result.isEmpty)
    }

    func testAllTracksExceedMaxDurationReturnsEmpty() {
        let tracks = [
            makeTrack(id: 1, duration: 500, distance: 0.1),
            makeTrack(id: 2, duration: 600, distance: 0.2),
        ]

        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 300,
            tolerance: 60,
            maxCandidates: 50
        ))

        let result = engine.pack(tracks: tracks, target: 300)
        XCTAssertTrue(result.isEmpty)
    }

    func testGreedyFallbackFillsToMinDuration() {
        // Phase 1 lookahead picks at most 3 tracks; if they total < minDuration,
        // the greedy phase should add remaining tracks that fit.
        let tracks = [
            makeTrack(id: 1, duration: 30, distance: 0.1),
            makeTrack(id: 2, duration: 30, distance: 0.2),
            makeTrack(id: 3, duration: 30, distance: 0.3),
            makeTrack(id: 4, duration: 30, distance: 0.4),
            makeTrack(id: 5, duration: 30, distance: 0.5),
            makeTrack(id: 6, duration: 30, distance: 0.6),
        ]

        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 150,
            tolerance: 30,
            maxCandidates: 50
        ))

        let result = engine.pack(tracks: tracks, target: 150)
        let total = engine.totalDuration(of: result)

        XCTAssertGreaterThanOrEqual(total, 120)
        XCTAssertLessThanOrEqual(total, 180)
    }

    func testExactTargetMatch() {
        let tracks = [
            makeTrack(id: 1, duration: 300, distance: 0.1),
            makeTrack(id: 2, duration: 300, distance: 0.2),
        ]

        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 600,
            tolerance: 0,
            maxCandidates: 50
        ))

        let result = engine.pack(tracks: tracks, target: 600)
        let total = engine.totalDuration(of: result)

        XCTAssertEqual(total, 600)
        XCTAssertEqual(result.count, 2)
    }

    func testUsesDefaultTargetFromConfig() {
        let tracks = [
            makeTrack(id: 1, duration: 1500, distance: 0.1),
            makeTrack(id: 2, duration: 1500, distance: 0.2),
        ]

        // default target = 25 min = 1500 s, tolerance 60 s
        let engine = PomodoroEngine()
        let result = engine.pack(tracks: tracks)
        let total = engine.totalDuration(of: result)

        // With 0-tolerance target and 3 min tolerance, two 25-min tracks should fit
        XCTAssertGreaterThanOrEqual(total, 1440)
        XCTAssertLessThanOrEqual(total, 1560)
    }

    // MARK: - Structural Integrity

    func testTotalDurationCalculatesCorrectly() {
        let tracks = [
            makeTrack(id: 1, duration: 60, distance: 0.1),
            makeTrack(id: 2, duration: 120, distance: 0.2),
            makeTrack(id: 3, duration: 90, distance: 0.3),
        ]

        let engine = PomodoroEngine()
        let total = engine.totalDuration(of: tracks)
        XCTAssertEqual(total, 270)
    }

    func testPackResultsAreValidPlexTracks() {
        let tracks = [
            makeTrack(id: 1, duration: 180, distance: 0.1),
            makeTrack(id: 2, duration: 240, distance: 0.2),
        ]

        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 300,
            tolerance: 60,
            maxCandidates: 50
        ))

        let result = engine.pack(tracks: tracks, target: 300)

        for track in result {
            XCTAssertFalse(track.id.isEmpty)
            XCTAssertFalse(track.title.isEmpty)
            XCTAssertGreaterThan(track.duration, 0)
        }
    }
}

final class DeduplicateTests: XCTestCase {
    func makeTrack(id: Int, title: String, artist: String = "Artist") -> Track {
        Track(
            id: String(id),
            title: title,
            artist: artist,
            album: "Album",
            duration: 180_000,
            key: "",
            thumb: nil,
            score: nil
        )
    }

    func testDeduplicateRemovesExactDuplicates() {
        let tracks = [
            makeTrack(id: 1, title: "Song A"),
            makeTrack(id: 1, title: "Song A"),
            makeTrack(id: 2, title: "Song B"),
        ]

        let result = deduplicate(tracks: tracks)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, "1")
        XCTAssertEqual(result[1].id, "2")
    }

    func testDeduplicatePreservesUniqueTracks() {
        let tracks = [
            makeTrack(id: 1, title: "Song A"),
            makeTrack(id: 2, title: "Song B"),
            makeTrack(id: 3, title: "Song C"),
        ]

        let result = deduplicate(tracks: tracks)
        XCTAssertEqual(result.count, 3)
    }

    func testDeduplicateSameIdDifferentTitle() {
        let tracks = [
            makeTrack(id: 1, title: "Song A"),
            makeTrack(id: 1, title: "Song B"),
        ]

        let result = deduplicate(tracks: tracks)
        XCTAssertEqual(result.count, 2)
    }

    func testDeduplicateEmptyInput() {
        let result = deduplicate(tracks: [])
        XCTAssertTrue(result.isEmpty)
    }
}

final class ErrorDescriptionTests: XCTestCase {
    func testAllCasesReturnNonEmptyDescription() {
        let cases: [PlexodoroError] = [
            .serverUnreachable,
            .noCurrentTrack,
            .noSonicAnalysis,
            .noAudioURL,
            .playbackFailed,
        ]

        for error in cases {
            let desc = error.errorDescription
            XCTAssertNotNil(desc)
            XCTAssertFalse(desc!.isEmpty, "\(error) should have a non-empty description")
        }
    }
}
