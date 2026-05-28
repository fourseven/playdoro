import XCTest
import Foundation
@testable import Plexodoro

final class PomodoroEngineTests: XCTestCase {
    func makeTrack(id: Int, duration: TimeInterval, distance: Double = 1.0) -> PlexTrack {
        PlexTrack(
            id: id,
            title: "Track \(id)",
            artist: "Artist",
            album: "Album",
            duration: duration * 1000,
            thumb: nil,
            distance: distance
        )
    }

    func testPacksTracksWithinTargetRange() {
        let tracks = [
            makeTrack(id: 1, duration: 180, distance: 0.1),
            makeTrack(id: 2, duration: 240, distance: 0.2),
            makeTrack(id: 3, duration: 200, distance: 0.3),
            makeTrack(id: 4, duration: 300, distance: 0.4),
            makeTrack(id: 5, duration: 210, distance: 0.5),
            makeTrack(id: 6, duration: 190, distance: 0.6),
        ]

        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 600,
            tolerance: 60,
            maxCandidates: 50
        ))

        let result = engine.pack(tracks: tracks, target: 600)
        let total = engine.totalDuration(of: result)

        XCTAssertGreaterThanOrEqual(total, 540)
        XCTAssertLessThanOrEqual(total, 660)
        XCTAssertFalse(result.isEmpty)
    }

    func testPrefersCloserMatches() {
        let tracks = [
            makeTrack(id: 1, duration: 300, distance: 0.1),
            makeTrack(id: 2, duration: 300, distance: 0.9),
            makeTrack(id: 3, duration: 300, distance: 0.2),
        ]

        let engine = PomodoroEngine(config: PomodoroConfig(
            targetDuration: 560,
            tolerance: 60,
            maxCandidates: 50
        ))

        let result = engine.pack(tracks: tracks, target: 560)
        let total = engine.totalDuration(of: result)

        XCTAssertGreaterThanOrEqual(total, 500)
        XCTAssertLessThanOrEqual(total, 620)
        XCTAssertEqual(result.first?.id, 1)
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

    func testReturnsLastTrackIfUnderMin() {
        let bigTrack = makeTrack(id: 1, duration: 1000, distance: 0.1)
        let engine = PomodoroEngine()
        let result = engine.pack(tracks: [bigTrack], target: 300)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, 1)
    }

    func testEmptyTracksReturnsEmpty() {
        let engine = PomodoroEngine()
        let result = engine.pack(tracks: [], target: 300)
        XCTAssertTrue(result.isEmpty)
    }

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
}
