import AVFoundation
import Foundation
import OSLog

private let log = Logger(subsystem: "com.mathewhartley.plexodoro", category: "AudioPlayer")

private final class CertDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

@MainActor
class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var isDownloading = false
    @Published var currentTrackIndex = 0
    @Published var downloadProgress: Double = 0

    private(set) var tracks: [PlexTrack] = []
    private var player: AVQueuePlayer?
    private var boundaryObserver: Any?
    private var itemEndObserver: NSObjectProtocol?
    private var hasHandledPlaylistEnd = false
    private var tempFiles: [URL] = []

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config, delegate: CertDelegate(), delegateQueue: nil)
    }()

    var onPlaylistFinished: (() -> Void)?
    var onStoppedAtTrackEnd: (() -> Void)?

    var remainingOnCurrentTrack: TimeInterval {
        guard let player = player, let item = player.currentItem else { return 0 }
        let duration = CMTimeGetSeconds(item.duration)
        let current = CMTimeGetSeconds(player.currentTime())
        guard duration.isFinite, current.isFinite else { return 0 }
        return max(0, duration - current)
    }

    func play(tracks: [PlexTrack], urls: [URL]) async {
        self.tracks = tracks
        currentTrackIndex = 0
        hasHandledPlaylistEnd = false
        downloadProgress = 0
        isDownloading = true

        log.log("Downloading \(tracks.count) tracks...")
        log.log("First URL: \(urls.first?.absoluteString ?? "none", privacy: .public)")

        var localURLs: [URL] = []
        for (i, url) in urls.enumerated() {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            components.scheme = "https"
            guard let realURL = components.url else { continue }

            do {
                let (data, response) = try await session.data(from: realURL)
                let mime = response.mimeType ?? "bin"
                let ext = realURL.pathExtension.isEmpty ? "bin" : realURL.pathExtension
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(i)_\(tracks[i].id)")
                    .appendingPathExtension(ext)
                try data.write(to: tempURL)
                localURLs.append(tempURL)
                self.tempFiles.append(tempURL)
                downloadProgress = Double(i + 1) / Double(urls.count)
                log.log("Downloaded \(i+1)/\(tracks.count): \(data.count) bytes (\(mime))")
            } catch {
                log.error("Download failed for track \(i): \(error.localizedDescription, privacy: .public)")
                continue
            }
        }

        isDownloading = false

        guard !localURLs.isEmpty else {
            log.error("No tracks downloaded")
            return
        }

        log.log("Creating AVPlayer with \(localURLs.count) local files")
        let items = localURLs.map(AVPlayerItem.init)
        let queuePlayer = AVQueuePlayer(items: items)
        self.player = queuePlayer

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard let player = self.player, !self.hasHandledPlaylistEnd else { return }

                if !player.items().isEmpty {
                    self.currentTrackIndex = self.tracks.count - player.items().count
                    log.log("Track ended, now at index \(self.currentTrackIndex)")
                } else if !self.tracks.isEmpty {
                    self.hasHandledPlaylistEnd = true
                    self.currentTrackIndex = self.tracks.count - 1
                    self.isPlaying = false
                    log.log("Playlist finished")
                    self.onPlaylistFinished?()
                }
            }
        }

        queuePlayer.play()
        isPlaying = true
        log.log("AVQueuePlayer.play() called, rate=\(queuePlayer.rate)")
    }

    func stopAfterCurrentTrack() {
        guard let player = player, let currentItem = player.currentItem else {
            stop()
            onStoppedAtTrackEnd?()
            return
        }

        removeBoundaryObserver()

        let endTime = CMTimeMultiplyByFloat64(currentItem.duration, multiplier: 0.99)
        boundaryObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: endTime)],
            queue: .main
        ) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.stop()
                self.onStoppedAtTrackEnd?()
            }
        }
    }

    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            log.log("Paused")
        } else {
            player.play()
            isPlaying = true
            log.log("Resumed")
        }
    }

    func stop() {
        log.log("Stopping playback")
        removeObservers()
        player?.pause()
        player?.removeAllItems()
        isPlaying = false
        cleanupTempFiles()
    }

    private func cleanupTempFiles() {
        for url in tempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        tempFiles = []
    }

    private func removeBoundaryObserver() {
        guard let observer = boundaryObserver else { return }
        player?.removeTimeObserver(observer)
        boundaryObserver = nil
    }

    private func removeObservers() {
        removeBoundaryObserver()
        if let observer = itemEndObserver {
            NotificationCenter.default.removeObserver(observer)
            itemEndObserver = nil
        }
    }
}
