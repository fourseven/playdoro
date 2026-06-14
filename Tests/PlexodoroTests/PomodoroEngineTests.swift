import XCTest
import Foundation
@testable import PlexodoroKit

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

final class MultiSeedEngineTests: XCTestCase {
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

    func testPackRetainsAllSeeds() {
        let seeds = [makeTrack(id: 1, duration: 180), makeTrack(id: 2, duration: 200)]
        let candidates = (3...20).map { makeTrack(id: $0, duration: 60, distance: Double($0) * 0.1) }

        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 1500,
            tolerance: 60,
            maxCandidates: 50
        ))

        let result = engine.pack(tracks: candidates, mustInclude: seeds, target: 1500)

        for seed in seeds {
            XCTAssertTrue(result.contains(where: { $0.id == seed.id }), "seed \(seed.id) missing from result")
        }
    }

    func testPackReservesSeedDuration() {
        let seeds = [makeTrack(id: 1, duration: 300), makeTrack(id: 2, duration: 300)]
        let candidates = (3...30).map { makeTrack(id: $0, duration: 60, distance: Double($0) * 0.1) }

        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 1200,
            tolerance: 60,
            maxCandidates: 50
        ))

        let result = engine.pack(tracks: candidates, mustInclude: seeds, target: 1200)
        let total = engine.totalDuration(of: result)

        XCTAssertLessThanOrEqual(total, 1200 + 60)
        XCTAssertGreaterThanOrEqual(total, 1200 - 60)

        let packedOnly = result.filter { $0.id != "1" && $0.id != "2" }
        for track in packedOnly {
            XCTAssertFalse(seeds.contains(where: { $0.id == track.id }))
        }
    }

    func testPackWithEmptyMustIncludeStaysWithinBounds() {
        let candidates = (1...20).map { makeTrack(id: $0, duration: 60, distance: Double($0) * 0.1) }

        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 600,
            tolerance: 60,
            maxCandidates: 50
        ))

        let result = engine.pack(tracks: candidates, mustInclude: [], target: 600)
        let total = engine.totalDuration(of: result)

        XCTAssertGreaterThanOrEqual(total, 540)
        XCTAssertLessThanOrEqual(total, 660)
        XCTAssertEqual(Set(result.map(\.id)).count, result.count, "expected no duplicate ids")
    }
}

final class MergeNearestResultsTests: XCTestCase {
    func makeTrack(id: Int) -> Track {
        Track(
            id: String(id),
            title: "Track \(id)",
            artist: "Artist",
            album: "Album",
            duration: 180_000,
            key: "",
            thumb: nil,
            score: nil
        )
    }

    func testMergesBatchesAndDedupes() {
        let a = [makeTrack(id: 1), makeTrack(id: 2), makeTrack(id: 3)]
        let b = [makeTrack(id: 2), makeTrack(id: 4)]
        let c = [makeTrack(id: 5)]

        let result = mergeNearestResults([a, b, c])

        XCTAssertEqual(result.map(\.id), ["1", "2", "3", "4", "5"])
    }

    func testEmptyAndNonEmptyCombinations() {
        let track = makeTrack(id: 1)

        XCTAssertEqual(mergeNearestResults([]), [])
        XCTAssertEqual(mergeNearestResults([[], []]), [])
        XCTAssertEqual(mergeNearestResults([[], [track]]).map(\.id), ["1"])
        XCTAssertEqual(mergeNearestResults([[track], []]).map(\.id), ["1"])
    }

    func testPreservesFirstOccurrenceOrder() {
        let a = [makeTrack(id: 9), makeTrack(id: 1)]
        let b = [makeTrack(id: 1), makeTrack(id: 9)]

        let result = mergeNearestResults([a, b])

        XCTAssertEqual(result.map(\.id), ["9", "1"])
    }
}

final class SavedPlaylistsTests: XCTestCase {
    func makeTrack(id: Int) -> Track {
        Track(
            id: String(id),
            title: "Track \(id)",
            artist: "Artist",
            album: "Album",
            duration: 180_000,
            key: "",
            thumb: nil,
            score: nil
        )
    }

    func makePlaylist(id: UUID = UUID(), date: Date = Date(), seedIds: [Int]) -> SeedPlaylist {
        SeedPlaylist(id: id, savedAt: date, seeds: seedIds.map { makeTrack(id: $0) })
    }

    func testEmptyExistingPrependsNew() {
        let added = makePlaylist(seedIds: [1, 2])
        let result = mergeSavedPlaylists(existing: [], added: added, maxRetained: 3)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, added.id)
    }

    func testCapsAtMaxRetained() {
        let a = makePlaylist(seedIds: [1])
        let b = makePlaylist(seedIds: [2])
        let c = makePlaylist(seedIds: [3])
        let d = makePlaylist(seedIds: [4])
        let result = mergeSavedPlaylists(existing: [a, b, c], added: d, maxRetained: 3)
        XCTAssertEqual(result.map(\.id), [d.id, a.id, b.id])
    }

    func testDedupesBySignatureAndMovesToFront() {
        let original = makePlaylist(seedIds: [1, 2])
        let other = makePlaylist(seedIds: [3])
        let reRecorded = makePlaylist(seedIds: [1, 2])
        let result = mergeSavedPlaylists(
            existing: [original, other],
            added: reRecorded,
            maxRetained: 3
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, reRecorded.id)
        XCTAssertEqual(result[1].id, other.id)
    }

    func testSignatureIgnoresSeedOrder() {
        let a = makePlaylist(seedIds: [1, 2, 3])
        let b = makePlaylist(seedIds: [3, 1, 2])
        let result = mergeSavedPlaylists(existing: [a], added: b, maxRetained: 3)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, b.id)
    }

    func testCodableRoundTrip() throws {
        let original = makePlaylist(seedIds: [1, 2, 3])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SeedPlaylist.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testListCodableRoundTrip() throws {
        let original = [
            makePlaylist(seedIds: [1]),
            makePlaylist(seedIds: [2, 3]),
            makePlaylist(seedIds: [4, 5, 6]),
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([SeedPlaylist].self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
