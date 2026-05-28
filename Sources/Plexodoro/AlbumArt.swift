import Logging
import SwiftUI

private let log = Logger(label: "com.plexodoro.albumart")

private let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    return URLSession(configuration: config, delegate: CertDelegate(), delegateQueue: nil)
}()

private let cacheDirectory: URL = {
    let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("plexodoro/albumart", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        log.info("Cache dir: \(dir.path)")
    } catch {
        log.error("Failed to create cache dir: \(error.localizedDescription)")
    }
    return dir
}()

private let cacheLimit = 50 * 1024 * 1024

private func cachePath(for url: URL) -> URL {
    let key = url.absoluteString
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: ":", with: "_")
        .replacingOccurrences(of: "?", with: "_")
        .replacingOccurrences(of: "&", with: "_")
        .replacingOccurrences(of: "=", with: "_")
        .replacingOccurrences(of: "%", with: "_")
    return cacheDirectory.appendingPathComponent(key)
}

private func evictIfNeeded() {
    guard let enumerator = FileManager.default.enumerator(
        at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
        options: .skipsHiddenFiles
    ) else {
        log.warning("evictIfNeeded: could not enumerate cache dir")
        return
    }

    var files: [(url: URL, date: Date, size: Int)] = []
    var totalSize = 0

    for case let file as URL in enumerator {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let fileSize = attrs[.size] as? Int,
              let modDate = attrs[.modificationDate] as? Date
        else { continue }
        files.append((file, modDate, fileSize))
        totalSize += fileSize
    }

    guard totalSize > cacheLimit else { return }

    log.info("Cache \(ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)) exceeds \(ByteCountFormatter.string(fromByteCount: Int64(cacheLimit), countStyle: .file)), evicting…")
    files.sort { $0.date < $1.date }
    var evicted = 0
    for file in files {
        do {
            try FileManager.default.removeItem(at: file.url)
            evicted += 1
        } catch {
            log.error("Failed to evict \(file.url.lastPathComponent): \(error.localizedDescription)")
        }
        totalSize -= file.size
        if totalSize <= cacheLimit { break }
    }
    log.info("Evicted \(evicted) files")
}

struct AlbumArt: View {
    let url: URL?
    @State private var imageData: Data?

    var body: some View {
        Group {
            if let data = imageData {
                #if os(macOS)
                if let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                #else
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                #endif
            } else if url != nil {
                Color(.systemFill)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            } else {
                Color(.systemFill)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.title)
                            .foregroundColor(.secondary)
                    }
            }
        }
        .task(id: url) {
            imageData = nil
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = url, imageData == nil else { return }
        let cached = cachePath(for: url)
        if FileManager.default.fileExists(atPath: cached.path) {
            imageData = try? Data(contentsOf: cached)
            log.info("Cache hit: \(cached.lastPathComponent) (\(imageData?.count ?? 0) bytes)")
            return
        }
        log.info("Cache miss, fetching: \(url.absoluteString)")
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                log.error("Non-HTTP response for \(url.absoluteString)")
                return
            }
            log.info("Downloaded \(data.count) bytes (HTTP \(httpResponse.statusCode))")
            imageData = data
            try data.write(to: cached)
            log.info("Cached to \(cached.lastPathComponent)")
            evictIfNeeded()
        } catch {
            log.error("Failed to download \(url.absoluteString): \(error.localizedDescription)")
        }
    }
}
