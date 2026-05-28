import AVFoundation
import Foundation
import OSLog

private let log = Logger(subsystem: "com.mathewhartley.plexodoro", category: "AudioPlayer")
private let fileLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("plexodoro_audio_player.log")
private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()
private func fileLog(_ message: String) {
    log.log("\(message, privacy: .public)")
    let line = "[\(dateFormatter.string(from: Date()))] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: fileLogURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileLogURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: fileLogURL)
        }
    }
}
private func fileErr(_ message: String) {
    log.error("\(message, privacy: .public)")
    fileLog("ERROR: \(message)")
}

@MainActor
class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var downloadProgress: Double = 0

    private var player: AVQueuePlayer?
    private var boundaryObserver: Any?
    private var itemEndObservers: [NSObjectProtocol] = []
    private var itemStatusObservations: [NSKeyValueObservation] = []
    private var hasHandledPlaylistEnd = false
    private var tempFiles: [URL] = []
    private var playSessionID = UUID()
    private var playerItems: [AVPlayerItem] = []

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config, delegate: CertDelegate(), delegateQueue: nil)
    }()

    var onTrackFinished: (() -> Void)?
    var onPlaylistFinished: (() -> Void)?
    var onStoppedAtTrackEnd: (() -> Void)?

    var remainingOnCurrentTrack: TimeInterval {
        guard let player = player, let item = player.currentItem else { return 0 }
        let duration = CMTimeGetSeconds(item.duration)
        let current = CMTimeGetSeconds(player.currentTime())
        guard duration.isFinite, current.isFinite else { return 0 }
        return max(0, duration - current)
    }

    // MARK: - Downloads

    private func downloadTrack(_ i: Int, url: URL, track: Track) async -> URL? {
        fileLog("Downloading track \(i): \(track.title)")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            fileErr("Failed to create URLComponents for track \(i)")
            return nil
        }
        components.scheme = "https"
        guard let secureURL = components.url else {
            fileErr("Failed to resolve secure URL for track \(i)")
            return nil
        }

        do {
            let (data, response) = try await self.session.data(from: secureURL)
            if let httpResponse = response as? HTTPURLResponse {
                fileLog("  HTTP \(httpResponse.statusCode), \(data.count) bytes for track \(i)")
                guard httpResponse.statusCode == 200 else {
                    let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
                    fileErr("  HTTP \(httpResponse.statusCode) — body: \(preview)")
                    return nil
                }
            }
            guard data.count >= 1000 else {
                let preview = String(data: data, encoding: .utf8) ?? "<binary>"
                fileErr("  Too small (\(data.count) bytes): \(preview)")
                return nil
            }

            let ext = secureURL.pathExtension.isEmpty ? "bin" : secureURL.pathExtension
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(i)_\(track.id)")
                .appendingPathExtension(ext)
            try data.write(to: tempURL)
            fileLog("  Saved → \(tempURL.lastPathComponent)")
            tempFiles.append(tempURL)
            return tempURL
        } catch {
            let nsError = error as NSError
            fileErr("  Failed: \(error.localizedDescription)")
            fileErr("    URL: \(secureURL.absoluteString)")
            fileErr("    domain=\(nsError.domain) code=\(nsError.code)")
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                fileErr("    underlying: \(underlying.domain):\(underlying.code) \(underlying.localizedDescription)")
            }
            return nil
        }
    }

    func download(tracks: [Track], urls: [URL]) async -> [URL?] {
        try? FileManager.default.removeItem(at: fileLogURL)
        fileLog("Downloading \(tracks.count) tracks sequentially...")
        var results: [URL?] = []

        for (i, url) in urls.enumerated() {
            let result = await downloadTrack(i, url: url, track: tracks[i])
            results.append(result)
        }

        let successCount = results.compactMap({ $0 }).count
        fileLog("Downloads complete: \(successCount)/\(tracks.count) succeeded")
        return results
    }

    // MARK: - Playback

    func play(urls: [URL]) async {
        fileLog("play() called with \(urls.count) URLs")
        // Save the newly downloaded temp files before stop() cleans them up
        let savedTempFiles = tempFiles
        tempFiles = []
        stop()
        tempFiles = savedTempFiles

        let sessionID = UUID()
        playSessionID = sessionID
        hasHandledPlaylistEnd = false

        let items = urls.map(AVPlayerItem.init)
        self.playerItems = items

        // Observe each item's status so we know when they're ready
        for (i, item) in items.enumerated() {
            let obs = item.observe(\.status, options: [.new, .old]) { item, _ in
                let label = statusLabel(item.status)
                fileLog("Item \(i) status: \(item.status.rawValue) (\(label))")
                if item.status == .failed, let err = item.error {
                    fileErr("  Item \(i) error: \(err.localizedDescription)")
                    fileErr("  Error domain: \((err as NSError).domain), code: \((err as NSError).code)")
                }
            }
            itemStatusObservations.append(obs)
            fileLog("  Item \(i): url=\(urls[i].lastPathComponent)")
        }

        fileLog("Creating AVQueuePlayer(items:) with \(items.count) items")
        let queuePlayer = AVQueuePlayer(items: items)
        self.player = queuePlayer

        // Log the queue state
        fileLog("Queue items after creation: \(queuePlayer.items().count)")
        fileLog("Current item: \(queuePlayer.currentItem != nil ? "set" : "nil")")

        // Per-item end observers — each knows its own index
        for (index, item) in items.enumerated() {
            let observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                fileLog("AVPlayerItemDidPlayToEndTime for item \(index)")
                guard let self = self else { return }
                Task { @MainActor in
                    guard self.playSessionID == sessionID,
                          !self.hasHandledPlaylistEnd else {
                        fileLog("  Ignored (session mismatch or already handled)")
                        return
                    }

                    if index < items.count - 1 {
                        fileLog("  Track \(index) ended, signalling onTrackFinished")
                        self.onTrackFinished?()
                    } else {
                        fileLog("  Last track ended, playlist finished")
                        self.hasHandledPlaylistEnd = true
                        self.isPlaying = false
                        self.onPlaylistFinished?()
                    }
                }
            }
            itemEndObservers.append(observer)
        }

        fileLog("Calling queuePlayer.play()")
        queuePlayer.play()
        isPlaying = true
        fileLog("AVQueuePlayer rate after play: \(queuePlayer.rate)")
        fileLog("Current item after play: \(queuePlayer.currentItem != nil ? "\(queuePlayer.currentItem!.status.rawValue)" : "nil")")
    }

    func stopAfterCurrentTrack() {
        fileLog("stopAfterCurrentTrack() called")
        guard let player = player, let currentItem = player.currentItem else {
            fileLog("  No player or current item, calling stop() directly")
            stop()
            onStoppedAtTrackEnd?()
            return
        }

        removeBoundaryObserver()
        hasHandledPlaylistEnd = true

        let endTime = CMTimeMultiplyByFloat64(currentItem.duration, multiplier: 0.99)
        fileLog("  Setting boundary observer at \(CMTimeGetSeconds(endTime))s (99% of \(CMTimeGetSeconds(currentItem.duration))s)")
        boundaryObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: endTime)],
            queue: .main
        ) { [weak self] in
            fileLog("  Boundary observer fired — stopping")
            guard let self = self else { return }
            Task { @MainActor in
                self.stop()
                self.onStoppedAtTrackEnd?()
            }
        }
    }

    func togglePlayPause() {
        guard let player = player else {
            fileErr("togglePlayPause: no player")
            return
        }
        if isPlaying {
            fileLog("Pausing (rate was \(player.rate))")
            player.pause()
            isPlaying = false
            fileLog("  rate now \(player.rate)")
        } else {
            fileLog("Resuming")
            player.play()
            isPlaying = true
            fileLog("  rate now \(player.rate)")
        }
    }

    func stop() {
        fileLog("STOP — playSessionID was \(playSessionID)")
        playSessionID = UUID()
        removeObservers()
        player?.pause()
        fileLog("  player.pause(), rate=\(player?.rate ?? -1.0)")
        player?.removeAllItems()
        player = nil
        playerItems = []
        isPlaying = false
        cleanupTempFiles()
        fileLog("STOP complete")
    }

    // MARK: - Cleanup

    private func cleanupTempFiles() {
        fileLog("Cleaning up \(tempFiles.count) temp files")
        for url in tempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        tempFiles = []
    }

    private func removeBoundaryObserver() {
        guard let observer = boundaryObserver else { return }
        player?.removeTimeObserver(observer)
        boundaryObserver = nil
        fileLog("Boundary observer removed")
    }

    private func removeObservers() {
        removeBoundaryObserver()

        for observer in itemEndObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        itemEndObservers = []
        fileLog("Item end observers removed: all cleared")

        for obs in itemStatusObservations {
            obs.invalidate()
        }
        itemStatusObservations = []
        fileLog("Item status observations invalidated")
    }
}

private func statusLabel(_ status: AVPlayerItem.Status) -> String {
    switch status {
    case .unknown: return "unknown"
    case .readyToPlay: return "readyToPlay"
    case .failed: return "failed"
    @unknown default: return "unknown(\(status.rawValue))"
    }
}
