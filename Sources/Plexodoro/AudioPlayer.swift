import AVFoundation
import Foundation
import OSLog

private let log = Logger(subsystem: "com.mathewhartley.plexodoro", category: "AudioPlayer")

@MainActor
class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTrackIndex = 0

    private(set) var tracks: [PlexTrack] = []
    private var player: AVQueuePlayer?
    private var boundaryObserver: Any?
    private var itemEndObserver: NSObjectProtocol?
    private var hasHandledPlaylistEnd = false

    var onPlaylistFinished: (() -> Void)?
    var onStoppedAtTrackEnd: (() -> Void)?

    var remainingOnCurrentTrack: TimeInterval {
        guard let player = player, let item = player.currentItem else { return 0 }
        let duration = CMTimeGetSeconds(item.duration)
        let current = CMTimeGetSeconds(player.currentTime())
        guard duration.isFinite, current.isFinite else { return 0 }
        return max(0, duration - current)
    }

    func play(tracks: [PlexTrack], urls: [URL]) {
        self.tracks = tracks
        currentTrackIndex = 0
        hasHandledPlaylistEnd = false

        log.log("Playing \(tracks.count) tracks")
        log.log("First URL: \(urls.first?.absoluteString ?? "none", privacy: .public)")

        let items = urls.map(AVPlayerItem.init)
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
        log.log("AVQueuePlayer.play() called")
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

    func stop() {
        log.log("Stopping playback")
        removeObservers()
        player?.pause()
        player?.removeAllItems()
        isPlaying = false
    }

    func skipToNext() {
        player?.advanceToNextItem()
        if let player = player {
            currentTrackIndex = tracks.count - player.items().count
        }
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
