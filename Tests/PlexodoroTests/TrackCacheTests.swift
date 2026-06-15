import XCTest
import Foundation
@testable import PlexodoroKit

final class TrackCacheTests: XCTestCase {
    private var cacheDirectory: URL!

    override func setUp() {
        super.setUp()
        cacheDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        super.tearDown()
    }

    private func makeCache(maxSizeBytes: Int = 1024 * 1024) -> TrackCache {
        TrackCache(cacheDirectory: cacheDirectory, maxSizeBytes: maxSizeBytes)
    }

    private func makeTrack(id: String) -> Track {
        Track(
            id: id,
            title: "Track \(id)",
            artist: "Artist",
            album: "Album",
            duration: 1000,
            key: "/library/metadata/\(id)",
            thumb: nil,
            score: nil
        )
    }

    func testStoreAndRetrieve() async throws {
        let cache = makeCache()
        let track = makeTrack(id: "1")
        let data = Data("hello".utf8)

        let storedURL = try await cache.store(data: data, for: track, extension: "mp3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))

        let retrievedURL = await cache.localURL(for: track, extension: "mp3")
        XCTAssertEqual(retrievedURL, storedURL)
    }

    func testCacheMissReturnsNil() async {
        let cache = makeCache()
        let track = makeTrack(id: "missing")

        let url = await cache.localURL(for: track, extension: "mp3")
        XCTAssertNil(url)
    }

    func testCacheMissForDifferentExtension() async throws {
        let cache = makeCache()
        let track = makeTrack(id: "1")
        let data = Data("hello".utf8)

        _ = try await cache.store(data: data, for: track, extension: "mp3")

        let url = await cache.localURL(for: track, extension: "m4a")
        XCTAssertNil(url)
    }

    func testClearRemovesAllFiles() async throws {
        let cache = makeCache()
        let track = makeTrack(id: "1")
        _ = try await cache.store(data: Data("hello".utf8), for: track, extension: "mp3")

        try await cache.clear()

        let url = await cache.localURL(for: track, extension: "mp3")
        XCTAssertNil(url)
    }

    func testEvictsOldestFilesWhenOverLimit() async throws {
        let maxSize = 10
        let cache = makeCache(maxSizeBytes: maxSize)

        let track1 = makeTrack(id: "1")
        let track2 = makeTrack(id: "2")
        let track3 = makeTrack(id: "3")

        _ = try await cache.store(data: Data(repeating: 0, count: 4), for: track1, extension: "bin")
        _ = try await cache.store(data: Data(repeating: 0, count: 4), for: track2, extension: "bin")
        _ = try await cache.store(data: Data(repeating: 0, count: 4), for: track3, extension: "bin")

        // The cache should have evicted the oldest entry to stay under 10 bytes.
        let size = try await cache.totalSize()
        XCTAssertLessThanOrEqual(size, Int64(maxSize))

        let track1URL = await cache.localURL(for: track1, extension: "bin")
        let track2URL = await cache.localURL(for: track2, extension: "bin")
        let track3URL = await cache.localURL(for: track3, extension: "bin")

        XCTAssertNil(track1URL)
        XCTAssertNotNil(track2URL)
        XCTAssertNotNil(track3URL)
    }

    func testAccessingFileUpdatesRecency() async throws {
        let maxSize = 8
        let cache = makeCache(maxSizeBytes: maxSize)

        let track1 = makeTrack(id: "1")
        let track2 = makeTrack(id: "2")
        let track3 = makeTrack(id: "3")

        _ = try await cache.store(data: Data(repeating: 0, count: 4), for: track1, extension: "bin")
        _ = try await cache.store(data: Data(repeating: 0, count: 4), for: track2, extension: "bin")

        // Touch track1 so it becomes most-recently used.
        _ = await cache.localURL(for: track1, extension: "bin")

        // Adding track3 should evict track2 (the LRU), not track1.
        _ = try await cache.store(data: Data(repeating: 0, count: 4), for: track3, extension: "bin")

        let track1URL = await cache.localURL(for: track1, extension: "bin")
        let track2URL = await cache.localURL(for: track2, extension: "bin")
        let track3URL = await cache.localURL(for: track3, extension: "bin")

        XCTAssertNotNil(track1URL)
        XCTAssertNil(track2URL)
        XCTAssertNotNil(track3URL)
    }
}
