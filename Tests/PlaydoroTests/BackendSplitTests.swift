import XCTest
import Foundation
import Combine
@testable import PlaydoroKit

private struct StubStreamer: StreamProviding {
    let url: URL?
    func streamURL(for track: Track) -> URL? { url }
}

private struct SparseStreamer: StreamProviding {
    let excluded: Set<String>
    func streamURL(for track: Track) -> URL? {
        excluded.contains(track.id) ? nil : URL(string: "http://localhost/x.bin")!
    }
}

@MainActor
private final class BareBackend: PlaybackBackend, VolumeProviding {
    let capabilities: PlaybackCapabilities = []
    var isPlaying: Bool { false }
    var currentElapsed: TimeInterval { 0 }
    var currentDuration: TimeInterval { 0 }
    var currentProgress: Double { 0 }
    func play(tracks: [Track], totalSeconds: TimeInterval) async throws -> [Track] { tracks }
    func togglePlayPause() {}
    func pause() {}
    func stop() {}
    func stopAfterCurrentTrack() {}
    var onTrackFinished: ((Track) -> Void)?
    var onPlaylistFinished: ((Track?) -> Void)?
    var onStoppedAtTrackEnd: ((Track?) -> Void)?
    var onTrackDownloaded: ((Track) -> Void)?
    var volume: Float = 1.0
}

@MainActor
final class BackendSplitTests: XCTestCase {
    private func makeTrack(_ title: String = "track") -> Track {
        Track(id: title, title: title, artist: "A", album: "B", duration: 180_000, key: "key", thumb: nil, score: nil)
    }

    func testEngineBackendOffersEQAndVolume() {
        let backend = EnginePlaybackBackend(provider: StubStreamer(url: URL(string: "http://localhost/x.bin")!))
        XCTAssertTrue(backend.capabilities.contains(.eq))
        XCTAssertTrue(backend.capabilities.contains(.volume))
    }

    func testPlayThrowsWhenProviderHasNoStreamURL() async {
        let backend = EnginePlaybackBackend(provider: StubStreamer(url: nil))
        do {
            _ = try await backend.play(tracks: [makeTrack()], totalSeconds: 10)
            XCTFail("Expected noAudioURL error")
        } catch {
            guard case PlaydoroError.noAudioURL = error else {
                return XCTFail("Expected noAudioURL, got \(error)")
            }
        }
    }

    func testPlayThrowsWhenSomeTracksLackStreamURL() async {
        let backend = EnginePlaybackBackend(provider: SparseStreamer(excluded: ["missing"]))
        do {
            _ = try await backend.play(tracks: [makeTrack(), makeTrack("missing")], totalSeconds: 10)
            XCTFail("Expected noAudioURL error")
        } catch {
            guard case PlaydoroError.noAudioURL = error else {
                return XCTFail("Expected noAudioURL, got \(error)")
            }
        }
    }

    func testReportPlaybackDefaultsToNoOp() async throws {
        struct StubCatalog: MusicCatalog {
            func ping() async throws {}
            func searchTracks(query: String, limit: Int) async throws -> [Track] { [] }
            func getTrack(id: String) async throws -> Track? { nil }
            func getNearest(trackId: String, limit: Int) async throws -> [Track] { [] }
            func thumbURL(for track: Track) -> URL? { nil }
        }
        // Non-Plex providers get the extension default; it must not throw.
        try await StubCatalog().reportPlayback(for: makeTrack(), time: 1, duration: 2, state: .playing)
    }

    func testNonEngineCapabilitiesAreEmpty() {
        let backend = BareBackend()
        XCTAssertFalse(backend.capabilities.contains(.eq))
        XCTAssertFalse(backend.capabilities.contains(.volume))
    }
}