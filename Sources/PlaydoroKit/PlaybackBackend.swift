import Combine
import Foundation

/// Features beyond plain playback that a backend can offer. The UI hides
/// anything the active backend doesn't support — only the engine backend
/// (Plex streams) currently provides EQ and volume control.
struct PlaybackCapabilities: OptionSet, Sendable {
    let rawValue: Int

    static let eq = PlaybackCapabilities(rawValue: 1 << 0)
    static let volume = PlaybackCapabilities(rawValue: 1 << 1)

    static let engine: PlaybackCapabilities = [.eq, .volume]
}

/// Controls playback for a provider. All backends are main-actor objects: the
/// pomodoro clock and the UI drive these calls and consume the state events.
/// `play(tracks:totalSeconds:)` returns the tracks actually scheduled for
/// playback — providers may drop tracks that fail to load, and the caller
/// rebases the pomodoro clock onto the real playlist.
@MainActor
protocol PlaybackBackend: AnyObject, ObservableObject {
    /// Redeclared with the concrete publisher type so callers can subscribe
    /// through the existential without losing `Failure == Never`.
    var objectWillChange: ObservableObjectPublisher { get }

    var capabilities: PlaybackCapabilities { get }
    var isPlaying: Bool { get }
    var currentElapsed: TimeInterval { get }
    var currentDuration: TimeInterval { get }
    /// Progress through the current track in [0, 1].
    var currentProgress: Double { get }

    func play(tracks: [Track], totalSeconds: TimeInterval) async throws -> [Track]
    func togglePlayPause()
    func pause()
    func stop()
    func stopAfterCurrentTrack()

    var onTrackFinished: ((Track) -> Void)? { get set }
    var onPlaylistFinished: ((Track?) -> Void)? { get set }
    var onStoppedAtTrackEnd: ((Track?) -> Void)? { get set }
    var onTrackDownloaded: ((Track) -> Void)? { get set }
}

/// Backends whose audio is processed in-app (parametric EQ). Only the engine
/// backend conforms; everything else plays provider-raw audio and hides the EQ
/// surface.
@MainActor
protocol EQProviding: AnyObject {
    func applyEQ(preset: EQPreset)
    var currentEQPreset: EQPreset { get }
    func setEQEnabled(_ enabled: Bool)
    var eqEnabled: Bool { get }
}

/// Backends whose volume the app can control directly.
@MainActor
protocol VolumeProviding: AnyObject {
    var volume: Float { get set }
}