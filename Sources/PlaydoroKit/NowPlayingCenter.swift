#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import MediaPlayer

#if canImport(UIKit)
typealias NowPlayingImage = UIImage
#else
typealias NowPlayingImage = NSImage
#endif

/// Drives the system "Now Playing" surfaces: the iOS lock-screen / Control
/// Center card, and the macOS Control Center module + hardware media keys.
/// Owned and fed by `AppState`.
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
        // The key can arrive as play, pause, or toggle; all map to the same
        // idempotent toggle. Enabled handlers also advertise us as a
        // now-playing source on macOS.
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand] {
            command.isEnabled = true
            command.addTarget(handler: toggle)
        }
        // Playdoro exposes no track-skip/seek/rate commands — the pomodoro
        // engine owns playlist order. Disabling them hides the corresponding
        // buttons from the control surface.
        for command in [
            center.nextTrackCommand, center.previousTrackCommand,
            center.seekForwardCommand, center.seekBackwardCommand,
            center.skipForwardCommand, center.skipBackwardCommand,
            center.changePlaybackPositionCommand,
            center.changePlaybackRateCommand, center.ratingCommand,
        ] {
            command.isEnabled = false
        }
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
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        // Keep the current artwork in place while a new one loads, so the card
        // doesn't flash blank between tracks.
        if let existing = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] {
            info[MPMediaItemPropertyArtwork] = existing
        }
        #if os(macOS)
        // Media keys route only to apps whose state is explicit; `.unknown`
        // hands them to Music/Safari (see IINA issue #3574).
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        #endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtwork(url: artworkURL)
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkURLKey = nil
        #if os(macOS)
        // Release now-playing ownership so the media keys fall back to other
        // apps (Music, the browser, …).
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func loadArtwork(url: URL?) {
        guard let url else { return }
        guard url.absoluteString != artworkURLKey else { return }
        artworkURLKey = url.absoluteString
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let data = await loadAlbumArtData(from: url) else { return }
            #if canImport(UIKit)
            guard let image = UIImage(data: data), !Task.isCancelled else { return }
            #else
            guard let image = NSImage(data: data), !Task.isCancelled else { return }
            #endif
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = Self.makeArtwork(image)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            self?.artworkTask = nil
        }
    }

    /// Builds the artwork in a non-isolated context so its `requestHandler`
    /// isn't main-actor-isolated — MediaPlayer invokes it on a background queue
    /// to render the art, which traps if the closure expects the main actor.
    private nonisolated static func makeArtwork(_ image: NowPlayingImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
