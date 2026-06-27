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

    /// Regression: the same song returned by Plex with different ids (e.g. it
    /// lives on both a studio album and a compilation, or in two libraries)
    /// must collapse to a single playlist entry. Pre-fix `deduplicate` keyed on
    /// `id-title-artist`, so distinct ids kept both copies and the packed
    /// playlist contained the same song twice.
    func testDeduplicateSameSongDifferentIdAndAlbum() {
        let studio = Track(
            id: "1", title: "Song A", artist: "Artist",
            album: "Studio Album", duration: 180_000,
            key: "/library/metadata/1", thumb: nil, score: nil
        )
        let compilation = Track(
            id: "2", title: "Song A", artist: "Artist",
            album: "Greatest Hits", duration: 180_000,
            key: "/library/metadata/2", thumb: nil, score: nil
        )
        let other = Track(
            id: "3", title: "Song B", artist: "Artist",
            album: "Studio Album", duration: 180_000,
            key: "/library/metadata/3", thumb: nil, score: nil
        )

        let result = deduplicate(tracks: [studio, compilation, other])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.title), ["Song A", "Song B"])
    }

    /// Trivial metadata drift (case, surrounding whitespace) must not defeat
    /// song-level dedup. Plex tags are not always consistent across albums.
    func testDeduplicateNormalizesCaseAndWhitespace() {
        let a = Track(
            id: "1", title: " Song A ", artist: "Artist",
            album: "Album", duration: 180_000,
            key: "", thumb: nil, score: nil
        )
        let b = Track(
            id: "2", title: "song a", artist: " artist ",
            album: "Album", duration: 180_000,
            key: "", thumb: nil, score: nil
        )

        let result = deduplicate(tracks: [a, b])

        XCTAssertEqual(result.count, 1)
    }
}

final class DeduplicateForPackingTests: XCTestCase {
    func makeTrack(id: Int, title: String, artist: String = "Artist", duration: TimeInterval = 180) -> Track {
        Track(
            id: String(id), title: title, artist: artist, album: "Album",
            duration: duration * 1000, key: "", thumb: nil, score: nil
        )
    }

    /// Regression: dedupe must run BEFORE packing, not after. Deduping after
    /// packing removes tracks the engine already counted toward the target
    /// duration, so the playlist starts short (25 min target → ~20 min actual).
    /// Pre-deduped candidates feed the engine, so it fills to target with
    /// unique songs and no post-pack drop occurs.
    func testExcludesCandidatesMatchingSeedsBySong() {
        let seed = makeTrack(id: 1, title: "Song A")
        let dupeCandidate = makeTrack(id: 2, title: "Song A", artist: "Artist")  // same song, different id
        let unique = makeTrack(id: 3, title: "Song B")

        let result = deduplicateForPacking(candidates: [dupeCandidate, unique], seeds: [seed])

        XCTAssertEqual(result.map(\.id), ["3"], "candidate same-song-as-seed should be excluded")
    }

    func testDedupesCandidatesAmongThemselves() {
        let candidates = [
            makeTrack(id: 1, title: "Song A"),
            makeTrack(id: 2, title: "Song A"),  // same song, different id/album
            makeTrack(id: 3, title: "Song B"),
        ]

        let result = deduplicateForPacking(candidates: candidates, seeds: [])

        XCTAssertEqual(result.map(\.id), ["1", "3"])
    }

    func testEmptyCandidatesAndSeeds() {
        XCTAssertTrue(deduplicateForPacking(candidates: [], seeds: []).isEmpty)
    }

    /// The whole point: after pre-dedup, the packed playlist must still reach
    /// the target duration — dedup must not shorten it.
    func testPackedDurationStaysAtTargetAfterDedup() {
        // 8 candidates where tracks 5 and 6 are the same song as 1 and 2.
        let candidates = (1...8).map { makeTrack(id: $0, title: "Song \($0)", duration: 200) }
            + [makeTrack(id: 9, title: "Song 1", duration: 200),  // dup of id 1
               makeTrack(id: 10, title: "Song 2", duration: 200)] // dup of id 2

        let deduped = deduplicateForPacking(candidates: candidates, seeds: [])
        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 1200, tolerance: 60, maxCandidates: 50
        ))
        let packed = engine.pack(tracks: deduped, mustInclude: [], target: 1200)
        let total = engine.totalDuration(of: packed)

        // 1200 target, ±60 tolerance. Pre-fix post-pack dedup would have dropped
        // the two dupes (400s) and landed at ~800s — well under min 1140.
        XCTAssertGreaterThanOrEqual(total, 1140, "packed duration must reach min after pre-dedup; got \(total)")
        XCTAssertLessThanOrEqual(total, 1260)
    }
}

final class ErrorDescriptionTests: XCTestCase {
    func testAllCasesReturnNonEmptyDescription() {
        let cases: [PlexodoroError] = [
            .serverUnreachable,
            .trackUnavailable,
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

final class NormalizeBatchScoresTests: XCTestCase {
    func makeTrack(id: Int, distance: Double?) -> Track {
        Track(
            id: String(id),
            title: "Track \(id)",
            artist: "Artist",
            album: "Album",
            duration: 180_000,
            key: "",
            thumb: nil,
            score: distance
        )
    }

    func testMinMaxMapsClosestToZeroFarthestToOne() {
        // min=0.2, max=0.8, range=0.6 → closest maps to 0, farthest to 1
        let batch = [
            makeTrack(id: 1, distance: 0.2),
            makeTrack(id: 2, distance: 0.5),
            makeTrack(id: 3, distance: 0.8),
        ]
        let result = normalizeBatchScores(batch)
        XCTAssertEqual(try XCTUnwrap(result[0].score), 0.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(result[1].score), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(result[2].score), 1.0, accuracy: 1e-9)
    }

    func testMakesScoresComparableAcrossSeeds() {
        // Seed A: tight rap cluster (tiny distances). Seed B: varied pop.
        // After min-max normalization both spans [0, 1] AND each seed's closest
        // maps to 0 — so the best match from every seed ties at the front.
        let a = normalizeBatchScores([
            makeTrack(id: 1, distance: 0.01),
            makeTrack(id: 2, distance: 0.02),
            makeTrack(id: 3, distance: 0.04),
        ])
        let b = normalizeBatchScores([
            makeTrack(id: 9, distance: 0.50),
            makeTrack(id: 10, distance: 0.75),
            makeTrack(id: 11, distance: 1.00),
        ])
        XCTAssertEqual(try XCTUnwrap(a.first?.score), 0.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.first?.score), 0.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(a.last?.score), 1.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(b.last?.score), 1.0, accuracy: 1e-9)
    }

    func testNilScoresLeftUntouched() {
        // Only one scored track → no reference frame, so scored value is
        // preserved as-is rather than inflated to 1.0.
        let batch = [
            makeTrack(id: 1, distance: nil),
            makeTrack(id: 2, distance: 0.5),
        ]
        let result = normalizeBatchScores(batch)
        XCTAssertNil(result[0].score)
        XCTAssertEqual(try XCTUnwrap(result[1].score), 0.5, accuracy: 1e-9)
    }

    func testAllNilScoresReturnsBatchAsIs() {
        let batch = [makeTrack(id: 1, distance: nil), makeTrack(id: 2, distance: nil)]
        let result = normalizeBatchScores(batch)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.score == nil })
    }

    func testSingleTrackBatchUnchanged() {
        let batch = [makeTrack(id: 1, distance: 0.5)]
        let result = normalizeBatchScores(batch)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(try XCTUnwrap(result[0].score), 0.5, accuracy: 1e-9)
    }

    func testAllEqualDistancesReturnsUnchanged() {
        // No spread (hi == lo) → nothing to normalize.
        let batch = [makeTrack(id: 1, distance: 0.4), makeTrack(id: 2, distance: 0.4)]
        let result = normalizeBatchScores(batch)
        XCTAssertEqual(result.map { $0.score ?? -1 }, [0.4, 0.4])
    }
}

final class InterleaveNearestResultsTests: XCTestCase {
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

    func testRoundRobinsAcrossBatches() {
        let a = [makeTrack(id: 1), makeTrack(id: 2), makeTrack(id: 3)]
        let b = [makeTrack(id: 4), makeTrack(id: 5), makeTrack(id: 6)]
        let c = [makeTrack(id: 7), makeTrack(id: 8), makeTrack(id: 9)]

        let result = interleaveNearestResults([a, b, c])

        XCTAssertEqual(result.map(\.id), ["1", "4", "7", "2", "5", "8", "3", "6", "9"])
    }

    func testHandlesUnequalBatchLengths() {
        let a = [makeTrack(id: 1), makeTrack(id: 2), makeTrack(id: 3)]
        let b = [makeTrack(id: 4)]

        let result = interleaveNearestResults([a, b])

        // Round 0: 1, 4. Round 1: 2. Round 2: 3.
        XCTAssertEqual(result.map(\.id), ["1", "4", "2", "3"])
    }

    func testDedupesFirstOccurrenceWins() {
        let a = [makeTrack(id: 1), makeTrack(id: 2)]
        let b = [makeTrack(id: 2), makeTrack(id: 3)]

        let result = interleaveNearestResults([a, b])

        XCTAssertEqual(result.map(\.id), ["1", "2", "3"])
    }

    func testEmptyInputs() {
        XCTAssertTrue(interleaveNearestResults([]).isEmpty)
        XCTAssertTrue(interleaveNearestResults([[], []]).isEmpty)
    }

    func testBalancesRegardlessOfBatchSize() {
        // Seed A floods with 9 tracks, seeds B and C have 2 each. Round-robin
        // still interleaves one-from-each per rank, not 9 A's in a row.
        let a = (1...9).map { makeTrack(id: $0) }
        let b = [makeTrack(id: 10), makeTrack(id: 11)]
        let c = [makeTrack(id: 12), makeTrack(id: 13)]

        let result = interleaveNearestResults([a, b, c])

        // First three must be one from each batch (ranks 0).
        XCTAssertEqual(Set(result.prefix(3).map(\.id)), ["1", "10", "12"])
        // No seed-A streak longer than 1 in the balanced head of the output.
        XCTAssertEqual(result.prefix(7).map(\.id), ["1", "10", "12", "2", "11", "13", "3"])
    }
}

final class CrossSeedBalanceTests: XCTestCase {
    /// Build a track tagged with its source seed (encoded in `album`) and a raw
    /// sonic distance from that seed.
    func seedTrack(id: Int, seed: String, distance: Double, duration: TimeInterval = 60) -> Track {
        Track(
            id: String(id),
            title: "Track \(id)",
            artist: "Artist \(seed)",
            album: seed,
            duration: duration * 1000,
            key: "",
            thumb: nil,
            score: distance
        )
    }

    /// Regression: with 3 diverse seeds where one (rap) clusters very tightly,
    /// the packed playlist must represent all three seeds rather than being
    /// flooded by the tightest cluster. Pre-fix the global score sort let the
    /// rap seed dominate; normalize + interleave + order-respecting pack fixes it.
    func testPackedSelectionRepresentsAllSeeds() {
        let rap = (1...8).map { seedTrack(id: $0, seed: "rap", distance: 0.01 * Double($0)) }
        let pop = (9...16).map { seedTrack(id: $0, seed: "pop", distance: 0.50 + 0.01 * Double($0)) }
        let rock = (17...24).map { seedTrack(id: $0, seed: "rock", distance: 0.80 + 0.01 * Double($0)) }

        let tracks = interleaveNearestResults([
            normalizeBatchScores(rap),
            normalizeBatchScores(pop),
            normalizeBatchScores(rock),
        ])

        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 480,
            tolerance: 60,
            maxCandidates: 50
        ))
        let result = engine.pack(tracks: tracks, target: 480)

        let seeds = Set(result.map(\.album))
        XCTAssertEqual(seeds, ["rap", "pop", "rock"], "expected all three seeds represented; got \(seeds)")
    }

    /// Stronger balance check: aggregated across many randomized runs the three
    /// seeds must split roughly evenly. Pre-fix the tightest (rap) cluster took
    /// ~100% of every packed playlist; post-fix each seed lands near 1/3. Per-run
    /// counts are noisy (small N), so we assert on the aggregate distribution.
    func testAggregateSelectionIsBalancedAcrossSeeds() {
        let rap = (1...10).map { seedTrack(id: $0, seed: "rap", distance: 0.01 * Double($0)) }
        let pop = (11...20).map { seedTrack(id: $0, seed: "pop", distance: 0.50 + 0.01 * Double($0 - 10)) }
        let rock = (21...30).map { seedTrack(id: $0, seed: "rock", distance: 0.80 + 0.01 * Double($0 - 20)) }

        let tracks = interleaveNearestResults([
            normalizeBatchScores(rap),
            normalizeBatchScores(pop),
            normalizeBatchScores(rock),
        ])
        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 540,
            tolerance: 60,
            maxCandidates: 50
        ))

        var totals: [String: Int] = ["rap": 0, "pop": 0, "rock": 0]
        var totalPicks = 0
        for _ in 0..<800 {
            for track in engine.pack(tracks: tracks, target: 540) {
                totals[track.album, default: 0] += 1
                totalPicks += 1
            }
        }

        XCTAssertGreaterThan(totalPicks, 0)
        // Expected ~1/3 each. Bounds [0.20, 0.45] tolerate sampling noise while
        // still catching the pre-fix regression where rap took ~99% of picks.
        for (seed, count) in totals {
            let share = Double(count) / Double(totalPicks)
            XCTAssertGreaterThan(share, 0.20, "seed \(seed) under-represented: \(share)")
            XCTAssertLessThan(share, 0.45, "seed \(seed) over-represented: \(share)")
        }
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

final class SelectionWeightTests: XCTestCase {
    func testMaxVarietyIsUniform() {
        // variety = 1 → every track weighs equally regardless of distance.
        let close = selectionWeight(score: 0.0, variety: 1)
        let mid = selectionWeight(score: 0.5, variety: 1)
        let far = selectionWeight(score: 1.0, variety: 1)
        XCTAssertEqual(close, mid, accuracy: 1e-9)
        XCTAssertEqual(mid, far, accuracy: 1e-9)
        XCTAssertEqual(close, 1.0, accuracy: 1e-9)
    }

    func testStrictVarietyPrefersClosest() {
        // variety = 0 → closest (score 0) dominates, farthest (score 1) gets 0.
        XCTAssertEqual(selectionWeight(score: 0.0, variety: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(selectionWeight(score: 1.0, variety: 0), 0.0, accuracy: 1e-9)
    }

    func testWeightMonotonicInScore() {
        // Lower distance (score) never weighs less than higher distance.
        for variety: Double in [0.0, 0.25, 0.5, 0.75] {
            let closer = selectionWeight(score: 0.2, variety: variety)
            let farther = selectionWeight(score: 0.8, variety: variety)
            XCTAssertGreaterThanOrEqual(closer, farther, "closer should outweigh farther at variety \(variety)")
        }
    }

    func testMidVarietySitsBetweenExtremes() {
        let s = 0.5
        let strict = selectionWeight(score: s, variety: 0)
        let mid = selectionWeight(score: s, variety: 0.5)
        let loose = selectionWeight(score: s, variety: 1)
        XCTAssertGreaterThan(loose, mid, "loose should outweigh mid")
        XCTAssertGreaterThan(mid, strict, "mid should outweigh strict")
    }

    func testClampsOutOfRange() {
        // variety < 0 behaves like 0; variety > 1 behaves like 1.
        XCTAssertEqual(selectionWeight(score: 0.5, variety: -1), selectionWeight(score: 0.5, variety: 0), accuracy: 1e-9)
        XCTAssertEqual(selectionWeight(score: 0.5, variety: 2), selectionWeight(score: 0.5, variety: 1), accuracy: 1e-9)
    }

    func testNilScoreTreatedAsFar() {
        // Unknown distance should weigh the same as the farthest track.
        XCTAssertEqual(selectionWeight(score: nil, variety: 0.5), selectionWeight(score: 1.0, variety: 0.5), accuracy: 1e-9)
    }

    func testCloserAlwaysBeatsFarAtStrict() {
        // Even a very close-ish track (0.1) should outweigh a far one (0.9) at strict.
        XCTAssertGreaterThan(selectionWeight(score: 0.1, variety: 0), selectionWeight(score: 0.9, variety: 0))
    }
}

final class VarietySelectionTests: XCTestCase {
    func makeRankedTrack(_ rank: Int, of total: Int, duration: TimeInterval = 30) -> Track {
        Track(
            id: "t\(rank)",
            title: "Track \(rank)",
            artist: "Artist",
            album: "Album",
            duration: duration * 1000,
            key: "",
            thumb: nil,
            score: Double(rank) / Double(total - 1)
        )
    }

    /// High variety should roam further across the candidate pool than strict.
    /// Aggregated over many runs, variety=1 reaches distinctly more tracks than
    /// variety=0 (which stays near the sonically-nearest front). Comparative
    /// only — the absolute reach depends on the weight curve and pool spacing.
    func testHighVarietyReachesFurtherThanStrict() {
        let total = 40
        let batch = (0..<total).map { makeRankedTrack($0, of: total) }

        let strict = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 240, tolerance: 0, maxCandidates: 50, variety: 0
        ))
        let varied = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 240, tolerance: 0, maxCandidates: 50, variety: 1
        ))

        var strictSeen = Set<String>()
        var variedSeen = Set<String>()
        for _ in 0..<400 {
            for track in strict.pack(tracks: batch, target: 240) { strictSeen.insert(track.id) }
            for track in varied.pack(tracks: batch, target: 240) { variedSeen.insert(track.id) }
        }

        XCTAssertGreaterThan(variedSeen.count, strictSeen.count,
                             "high variety should reach more distinct tracks than strict")
    }

    /// Strict variety should, on average, pick lower-rank (closer) tracks than
    /// high variety — i.e. the mean selected rank is lower at variety=0.
    func testStrictPicksLowerRanksOnAverage() {
        let total = 20
        let batch = (0..<total).map { makeRankedTrack($0, of: total) }

        let strict = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 240, tolerance: 0, maxCandidates: 50, variety: 0
        ))
        let varied = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 240, tolerance: 0, maxCandidates: 50, variety: 1
        ))

        func meanRank(_ engine: PomodoroEngine) -> Double {
            var sum = 0
            var n = 0
            for _ in 0..<400 {
                for track in engine.pack(tracks: batch, target: 240) {
                    sum += Int(track.id.dropFirst()) ?? 0
                    n += 1
                }
            }
            return n > 0 ? Double(sum) / Double(n) : 0
        }

        XCTAssertLessThan(meanRank(strict), meanRank(varied),
                          "strict should pick closer (lower-rank) tracks on average")
    }
}
