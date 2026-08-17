import Foundation

/// On-disk LRU cache for downloaded audio files.
///
/// Files are keyed by track id and stored in the app caches directory. The cache is bounded by
/// total byte size; when storing a new file would exceed the limit, the least-recently touched
/// files are removed until the cache fits.
actor TrackCache {
    static let defaultMaxSizeBytes = 500 * 1024 * 1024

    private let cacheDirectory: URL
    private let maxSizeBytes: Int

    init(maxSizeBytes: Int = defaultMaxSizeBytes) {
        self.maxSizeBytes = maxSizeBytes
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = caches.appendingPathComponent(AppIdentity.key("trackcache"), isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Internal initializer for tests so they can use a temporary directory.
    init(cacheDirectory: URL, maxSizeBytes: Int) {
        self.cacheDirectory = cacheDirectory
        self.maxSizeBytes = maxSizeBytes
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Returns a local file URL if the track is already cached, updating its access time.
    func localURL(for track: Track, extension ext: String?) -> URL? {
        let url = fileURL(for: track.id, extension: ext)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        touch(url)
        return url
    }

    /// Writes data to the cache and evicts old entries if the size limit is exceeded.
    func store(data: Data, for track: Track, extension ext: String?) throws -> URL {
        let url = fileURL(for: track.id, extension: ext)
        try data.write(to: url, options: .atomic)
        try evictIfNeeded()
        return url
    }

    /// Removes all cached files.
    func clear() throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        )
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Total size of all cached files in bytes.
    func totalSize() throws -> Int64 {
        try cachedFiles().reduce(0) { $0 + $1.size }
    }

    private func fileURL(for id: String, extension ext: String?) -> URL {
        let fileExtension = ext?.isEmpty == false ? ext! : "bin"
        return cacheDirectory.appendingPathComponent("\(id).\(fileExtension)")
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func evictIfNeeded() throws {
        var files = try cachedFiles()
        var total = files.reduce(0) { $0 + $1.size }

        while total > maxSizeBytes, !files.isEmpty {
            let oldest = files.removeFirst()
            try? FileManager.default.removeItem(at: oldest.url)
            total -= oldest.size
        }
    }

    private func cachedFiles() throws -> [(url: URL, size: Int64, date: Date)] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            ), let size = values.fileSize else { return nil }
            return (
                url,
                Int64(size),
                values.contentModificationDate ?? Date.distantPast
            )
        }.sorted { $0.date < $1.date }
    }
}
