import AVFoundation
import Foundation
import Logging

private let log = Logger(label: "com.plexodoro.audioplayer")
private let fileLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("plexodoro_audio_player.log")
private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()
private func fileLog(_ message: String) {
    log.info("\(message)")
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
    log.error("\(message)")
    fileLog("ERROR: \(message)")
}

@MainActor
class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var downloadProgress: Double = 0
    @Published var currentProgress: Double = 0

    private var player: AVQueuePlayer?
    private var boundaryObserver: Any?
    private var itemEndObservers: [NSObjectProtocol] = []
    private var itemStatusObservations: [NSKeyValueObservation] = []
    private var hasHandledPlaylistEnd = false
    private var tempFiles: [URL] = []
    private var playSessionID = UUID()
    private var playerItems: [AVPlayerItem] = []
    private var playlistEndIndex = -1
    private var progressTimer: Timer?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config, delegate: CertDelegate(), delegateQueue: nil)
    }()

    var onTrackFinished: (() -> Void)?
    var onPlaylistFinished: (() -> Void)?
    var onStoppedAtTrackEnd: (() -> Void)?
    var onTrackDownloaded: ((Track) -> Void)?

    var remainingOnCurrentTrack: TimeInterval {
        guard let player = player, let item = player.currentItem else { return 0 }
        let duration = CMTimeGetSeconds(item.duration)
        let current = CMTimeGetSeconds(player.currentTime())
        guard duration.isFinite, current.isFinite else { return 0 }
        return max(0, duration - current)
    }

    // MARK: - Download Stream

    private struct LocalTrack {
        let track: Track
        let url: URL
    }

    private func downloadStream(tracks: [Track], urls: [URL]) -> AsyncStream<LocalTrack> {
        AsyncStream { continuation in
            Task {
                for (i, url) in urls.enumerated() {
                    if let localURL = await downloadTrack(i, url: url, track: tracks[i]) {
                        continuation.yield(LocalTrack(track: tracks[i], url: localURL))
                    }
                }
                continuation.finish()
            }
        }
    }

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

    // MARK: - Download & Play

    func downloadAndPlay(tracks: [Track], urls: [URL]) async -> [Track] {
        try? FileManager.default.removeItem(at: fileLogURL)
        fileLog("Downloading \(tracks.count) tracks, playing first immediately...")

        let sessionID = startNewSession()
        var successfulTracks: [Track] = []

        for await local in downloadStream(tracks: tracks, urls: urls) {
            guard playSessionID == sessionID else { return cancelSession() }
            enqueueDownloadedTrack(local: local, sessionID: sessionID, successfulTracks: &successfulTracks)
        }

        return finalizePlayback(successfulTracks: successfulTracks, expected: tracks.count)
    }

    private func startNewSession() -> UUID {
        stop()
        let sessionID = UUID()
        playSessionID = sessionID
        hasHandledPlaylistEnd = false
        playlistEndIndex = -1
        return sessionID
    }

    private func enqueueDownloadedTrack(local: LocalTrack, sessionID: UUID, successfulTracks: inout [Track]) {
        var track = local.track
        track.isDownloaded = true
        successfulTracks.append(track)
        onTrackDownloaded?(track)

        let item = AVPlayerItem(url: local.url)
        playerItems.append(item)

        let trackIndex = successfulTracks.count - 1
        addObservers(to: item, index: trackIndex, sessionID: sessionID)
        fileLog("  Item \(trackIndex): url=\(local.url.lastPathComponent)")

        if player == nil {
            fileLog("Creating AVQueuePlayer with first track")
            let queuePlayer = AVQueuePlayer(items: [item])
            self.player = queuePlayer
            queuePlayer.play()
            isPlaying = true
            startProgressUpdates()
            fileLog("Playback started, rate: \(queuePlayer.rate)")
        } else {
            player?.insert(item, after: nil)
            fileLog("Inserted track \(trackIndex), queue: \(player?.items().count ?? 0)")
        }
    }

    private func cancelSession() -> [Track] {
        fileLog("Session expired (stop was called), discarding remaining downloads")
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        tempFiles = []
        return []
    }

    private func finalizePlayback(successfulTracks: [Track], expected: Int) -> [Track] {
        let totalTracks = successfulTracks.count
        fileLog("Downloads complete: \(totalTracks)/\(expected) succeeded")

        guard totalTracks > 0 else {
            fileErr("No tracks downloaded successfully")
            return []
        }

        playlistEndIndex = totalTracks - 1

        if let player, player.items().isEmpty, isPlaying {
            fileLog("Queue already empty — signalling playlist end")
            hasHandledPlaylistEnd = true
            isPlaying = false
            onPlaylistFinished?()
        }

        return successfulTracks
    }

    private func addObservers(to item: AVPlayerItem, index: Int, sessionID: UUID) {
        let statusObs = item.observe(\.status, options: [.new, .old]) { item, _ in
            let label = statusLabel(item.status)
            fileLog("Item \(index) status: \(item.status.rawValue) (\(label))")
            if item.status == .failed, let err = item.error {
                fileErr("  Item \(index) error: \(err.localizedDescription)")
            }
        }
        itemStatusObservations.append(statusObs)

        let endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            fileLog("AVPlayerItemDidPlayToEndTime for track \(index)")
            guard let self = self else { return }
            Task { @MainActor in
                guard self.playSessionID == sessionID, !self.hasHandledPlaylistEnd else {
                    fileLog("  Ignored")
                    return
                }

                if index == self.playlistEndIndex {
                    fileLog("  Last track — playlist finished")
                    self.hasHandledPlaylistEnd = true
                    self.isPlaying = false
                    self.onPlaylistFinished?()
                } else {
                    fileLog("  Track ended, signalling onTrackFinished")
                    self.onTrackFinished?()
                }
            }
        }
        itemEndObservers.append(endObs)
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
        playlistEndIndex = -1
        stopProgressUpdates()
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

    // MARK: - Progress

    private func startProgressUpdates() {
        stopProgressUpdates()
        refreshProgress()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshProgress()
            }
        }
    }

    private func stopProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = nil
        currentProgress = 0
    }

    private func refreshProgress() {
        guard let player = player, let item = player.currentItem else {
            currentProgress = 0
            return
        }
        let duration = CMTimeGetSeconds(item.duration)
        let current = CMTimeGetSeconds(player.currentTime())
        guard duration.isFinite, current.isFinite, duration > 0 else {
            currentProgress = 0
            return
        }
        currentProgress = current / duration
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
