#if canImport(UIKit)
import MediaPlayer
import UIKit

/// Drives the iOS lock-screen / Control Center "Now Playing" card:
/// `MPNowPlayingInfoCenter` for metadata + artwork, `MPRemoteCommandCenter`
/// for the play/pause buttons. Owned and fed by `AppState`.
@MainActor
final class NowPlayingCenter {
    var onTogglePlayPause: (() -> Void)?

    private var artworkURLKey: String?
    private var artworkTask: Task<Void, Never>?

    func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let toggle: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus = { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }
        center.playCommand.addTarget(handler: toggle)
        center.pauseCommand.addTarget(handler: toggle)
        center.togglePlayPauseCommand.addTarget(handler: toggle)
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    func update(
        title: String,
        artist: String,
        album: String,
        durationSeconds: TimeInterval,
        elapsedSeconds: TimeInterval,
        isPlaying: Bool,
        artworkURL: URL?
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: durationSeconds,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        // Keep the current artwork in place while a new one loads, so the card
        // doesn't flash blank between tracks.
        if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = existing
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtwork(url: artworkURL)
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkURLKey = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func loadArtwork(url: URL?) {
        guard let url else { return }
        guard url.absoluteString != artworkURLKey else { return }
        artworkURLKey = url.absoluteString
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let data = await loadAlbumArtData(from: url),
                  let image = UIImage(data: data),
                  !Task.isCancelled else { return }
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = Self.makeArtwork(image)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            self?.artworkTask = nil
        }
    }

    /// Builds the artwork in a non-isolated context so its `requestHandler`
    /// isn't main-actor-isolated — MediaPlayer invokes it on a background queue
    /// to render the art, which traps if the closure expects the main actor.
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
#endif
