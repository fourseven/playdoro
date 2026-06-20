import AVFoundation
import Foundation
import Logging
#if canImport(UIKit)
import UIKit
#endif

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
    @Published var volume: Float = 1.0 {
        didSet { playerNode?.volume = volume }
    }

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var eq: AudioEQ?
    private var pendingEQPreset: EQPreset?

    private var audioFiles: [AVAudioFile] = []
    private var tracks: [Track] = []
    private var currentTrackIndex = -1
    private var playSessionID = UUID()
    private var hasHandledPlaylistEnd = false
    private var shouldStopAfterCurrentTrack = false
    private var progressTimer: Timer?
    private var accumulatedPlayTime: TimeInterval = 0
    private var lastTickTimestamp: Date?

    // Interruption / config-change handling for screen-lock & sleep wakeups.
    private var interruptionObserver: NSObjectProtocol?
    private var configChangeObserver: NSObjectProtocol?
    private var wasPlayingBeforeInterruption = false

    private let cache = TrackCache()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config, delegate: CertDelegate(), delegateQueue: nil)
    }()

    var onTrackFinished: (() -> Void)?
    var onPlaylistFinished: (() -> Void)?
    var onStoppedAtTrackEnd: (() -> Void)?
    var onTrackDownloaded: ((Track) -> Void)?

    init() {
        setupNotifications()
    }

    var remainingOnCurrentTrack: TimeInterval {
        guard currentTrackIndex < audioFiles.count else { return 0 }
        let duration = currentTrackDuration
        let current: TimeInterval
        if let last = lastTickTimestamp {
            current = accumulatedPlayTime + Date().timeIntervalSince(last)
        } else {
            current = accumulatedPlayTime
        }
        return max(0, duration - current)
    }

    // MARK: - Interruption Handling

    private func setupNotifications() {
        #if canImport(UIKit)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            // Extract Sendable bits on the main queue, then hop to the main
            // actor. Notification itself isn't Sendable, so we don't capture
            // it across the actor boundary.
            guard let userInfo = note.userInfo,
                  let typeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
            let optionsRaw = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            Task { @MainActor in
                self?.handleAudioSessionInterruption(type: type, optionsRaw: optionsRaw)
            }
        }
        #endif

        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The engine reference isn't Sendable; just signal the change
            // and let the handler inspect the (single) owned engine.
            Task { @MainActor in
                self?.handleEngineConfigurationChange()
            }
        }
    }

    #if canImport(UIKit)
    private func handleAudioSessionInterruption(type: AVAudioSession.InterruptionType, optionsRaw: UInt) {
        switch type {
        case .began:
            fileLog("Audio session interruption began")
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                // System already halted audio. Sync state without treating
                // this as a user pause — don't fold stale elapsed time into
                // accumulatedPlayTime since we don't know how far it got.
                lastTickTimestamp = nil
                playerNode?.pause()
                isPlaying = false
                stopProgressUpdates()
            }
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            let shouldResume = options.contains(.shouldResume)
            fileLog("Audio session interruption ended, shouldResume=\(shouldResume), wasPlaying=\(wasPlayingBeforeInterruption)")
            if wasPlayingBeforeInterruption, shouldResume {
                configureAudioSession()
                resumePlaybackAfterInterruption()
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }
    #endif

    private func handleEngineConfigurationChange() {
        guard let engine = engine else { return }
        fileLog("AVAudioEngine configuration change — isRunning=\(engine.isRunning)")
        // Fires on output device swap (macOS), sleep/wake, and audio
        // session route changes (iOS). The eqNode -> mainMixerNode
        // connection was set up against the previous device; after a
        // swap it can go silent even when the sample rate looks
        // unchanged. Reconnect with the mixer's current output format,
        // then reschedule from the saved position.
        //
        // engine.stop() flushes the playerNode's pending scheduleFile
        // completion handlers — they fire on the main actor and would
        // cascade through trackDidFinish(), ending the playlist. To
        // survive that, bump playSessionID first so the stale handlers
        // are filtered out by the session check in trackDidFinish().
        // resumePlaybackAfterInterruption() re-schedules under the new
        // session ID.
        guard lastTickTimestamp != nil, currentTrackIndex >= 0 else { return }
        // Don't accumulate during the outage — audio wasn't progressing.
        lastTickTimestamp = nil
        playSessionID = UUID()
        engine.stop()
        reconnectEQToOutput()
        resumePlaybackAfterInterruption()
    }

    /// Re-establish the EQ -> mainMixerNode connection. After an output
    /// device swap the existing connection can go silent even when the
    /// sample rate looks unchanged. We reconnect using the current
    /// audio file's processing format (the same format used in
    /// setupEngine), NOT the device's output format — AVAudioUnitEQ
    /// does not resample, so its input and output formats must match.
    /// The mainMixerNode handles conversion to the active device.
    private func reconnectEQToOutput() {
        guard let engine = engine, let eq = eq else { return }
        guard currentTrackIndex >= 0, currentTrackIndex < audioFiles.count else {
            fileLog("reconnectEQToOutput: no current audio file, skipping")
            return
        }
        let format = audioFiles[currentTrackIndex].processingFormat
        guard format.sampleRate > 0 else {
            fileErr("File format invalid — skipping reconnect")
            return
        }
        fileLog("Reconnecting EQ to mainMixerNode at \(format.sampleRate) Hz (file format)")
        engine.disconnectNodeOutput(eq.eqNode, bus: 0)
        engine.connect(eq.eqNode, to: engine.mainMixerNode, format: format)
    }

    /// Restart the engine (if stopped) and reschedule the current track from
    /// `accumulatedPlayTime`. Called after interruptions, engine config
    /// changes, or when the user presses play against a stopped engine
    /// (e.g. after the screen locked). Scheduled segments are cleared when
    /// the engine stops, so a plain `play()` would otherwise be silent.
    private func resumePlaybackAfterInterruption() {
        guard let engine = engine, let playerNode = playerNode else {
            fileErr("resumePlaybackAfterInterruption: no engine/player")
            return
        }
        guard currentTrackIndex >= 0, currentTrackIndex < audioFiles.count else {
            fileErr("resumePlaybackAfterInterruption: no current track")
            return
        }

        let file = audioFiles[currentTrackIndex]
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(accumulatedPlayTime * sampleRate)
        let remainingFrames = AVAudioFrameCount(max(0, Int64(file.length) - Int64(startFrame)))
        guard remainingFrames > 0 else {
            fileLog("Resume: track \(currentTrackIndex) already finished, advancing")
            trackDidFinish(index: currentTrackIndex, sessionID: playSessionID)
            return
        }

        if !engine.isRunning {
            do {
                try engine.start()
                fileLog("Engine restarted after stop")
            } catch {
                fileErr("Failed to restart engine: \(error.localizedDescription)")
                return
            }
        }

        let sessionID = playSessionID
        let index = currentTrackIndex
        playerNode.scheduleSegment(file, startingFrame: startFrame, frameCount: remainingFrames, at: nil) { [weak self] in
            Task { @MainActor in
                self?.trackDidFinish(index: index, sessionID: sessionID)
            }
        }
        playerNode.play()
        isPlaying = true
        resumeProgressUpdates()
        fileLog("Resumed at \(accumulatedPlayTime)s into track \(index), \(remainingFrames) frames remaining")
    }

    private func resumeProgressUpdates() {
        stopProgressUpdates()
        lastTickTimestamp = Date()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshProgress()
            }
        }
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

        let ext = secureURL.pathExtension.isEmpty ? "bin" : secureURL.pathExtension
        if let cachedURL = await cache.localURL(for: track, extension: ext) {
            fileLog("  Cache hit → \(cachedURL.lastPathComponent)")
            return cachedURL
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

            let localURL = try await cache.store(data: data, for: track, extension: ext)
            fileLog("  Saved → \(localURL.lastPathComponent)")
            return localURL
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

    private func configureAudioSession() {
        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    func downloadAndPlay(tracks: [Track], urls: [URL]) async -> [Track] {
        configureAudioSession()
        try? FileManager.default.removeItem(at: fileLogURL)
        fileLog("Downloading \(tracks.count) tracks, playing first immediately…")

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
        shouldStopAfterCurrentTrack = false
        audioFiles = []
        self.tracks = []
        currentTrackIndex = -1
        accumulatedPlayTime = 0
        lastTickTimestamp = nil
        return sessionID
    }

    private func enqueueDownloadedTrack(local: LocalTrack, sessionID: UUID, successfulTracks: inout [Track]) {
        var track = local.track
        track.isDownloaded = true
        successfulTracks.append(track)
        onTrackDownloaded?(track)

        guard let audioFile = try? AVAudioFile(forReading: local.url) else {
            fileErr("Failed to open audio file for \(local.url.lastPathComponent)")
            return
        }

        audioFiles.append(audioFile)
        self.tracks.append(track)
        let index = audioFiles.count - 1
        fileLog("  Audio file \(index): \(local.url.lastPathComponent), \(audioFile.length) frames @ \(audioFile.processingFormat.sampleRate) Hz")

        if engine == nil {
            setupEngine(with: audioFile.processingFormat)
        }

        scheduleFile(at: index, sessionID: sessionID)

        if index == 0 {
            currentTrackIndex = 0
            startEngineAndPlay(sessionID: sessionID)
        }
    }

    private func setupEngine(with format: AVAudioFormat) {
        fileLog("Setting up AVAudioEngine")
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let eq = AudioEQ()

        engine.attach(playerNode)
        engine.attach(eq.eqNode)

        engine.connect(playerNode, to: eq.eqNode, format: format)
        engine.connect(eq.eqNode, to: engine.mainMixerNode, format: format)

        playerNode.volume = volume

        if let preset = pendingEQPreset {
            eq.apply(preset: preset)
        }
        self.engine = engine
        self.playerNode = playerNode
        self.eq = eq
    }

    private func startEngineAndPlay(sessionID: UUID) {
        guard let engine = engine, let playerNode = playerNode else { return }
        do {
            try engine.start()
            playerNode.play()
            isPlaying = true
            startProgressUpdates()
            fileLog("Engine started and playback begun")
        } catch {
            fileErr("Failed to start audio engine: \(error.localizedDescription)")
            isPlaying = false
        }
    }

    private func scheduleFile(at index: Int, sessionID: UUID) {
        guard index < audioFiles.count else { return }
        let file = audioFiles[index]
        fileLog("Scheduling track \(index): \(file.url.lastPathComponent)")
        playerNode?.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor in
                self?.trackDidFinish(index: index, sessionID: sessionID)
            }
        }
    }

    private func trackDidFinish(index: Int, sessionID: UUID) {
        guard playSessionID == sessionID, !hasHandledPlaylistEnd else {
            fileLog("Track \(index) finished — ignored (session mismatch or already ended)")
            return
        }

        fileLog("Track \(index) finished")

        if shouldStopAfterCurrentTrack || index == audioFiles.count - 1 {
            hasHandledPlaylistEnd = true
            isPlaying = false
            stopProgressUpdates()
            if shouldStopAfterCurrentTrack {
                fileLog("Stopped after current track")
                stop()
                onStoppedAtTrackEnd?()
            } else {
                fileLog("Playlist finished")
                onPlaylistFinished?()
            }
        } else {
            currentTrackIndex = index + 1
            accumulatedPlayTime = 0
            lastTickTimestamp = isPlaying ? Date() : nil
            onTrackFinished?()
        }
    }

    private func cancelSession() -> [Track] {
        fileLog("Session expired (stop was called), discarding remaining downloads")
        return []
    }

    private func finalizePlayback(successfulTracks: [Track], expected: Int) -> [Track] {
        let totalTracks = successfulTracks.count
        fileLog("Downloads complete: \(totalTracks)/\(expected) succeeded")

        guard totalTracks > 0 else {
            fileErr("No tracks downloaded successfully")
            return []
        }

        if let engine = engine, !engine.isRunning, !isPlaying {
            fileLog("Engine not running after downloads — signalling playlist end")
            hasHandledPlaylistEnd = true
            onPlaylistFinished?()
        }

        return successfulTracks
    }

    func stopAfterCurrentTrack() {
        fileLog("stopAfterCurrentTrack() called")
        guard playerNode != nil, currentTrackIndex < audioFiles.count else {
            fileLog("  No player or current item, calling stop() directly")
            stop()
            onStoppedAtTrackEnd?()
            return
        }
        shouldStopAfterCurrentTrack = true
        fileLog("  Will stop after track \(currentTrackIndex)")
    }

    func pause() {
        guard let playerNode = playerNode else {
            fileErr("pause: no player")
            return
        }
        fileLog("Pausing")
        if let last = lastTickTimestamp {
            accumulatedPlayTime += Date().timeIntervalSince(last)
        }
        lastTickTimestamp = nil
        playerNode.pause()
        isPlaying = false
        refreshProgress()
    }

    func togglePlayPause() {
        guard let playerNode = playerNode else {
            fileErr("togglePlayPause: no player")
            return
        }
        if isPlaying {
            pause()
        } else {
            fileLog("Resuming")
            if let engine = engine, !engine.isRunning {
                // Engine stopped while paused (screen lock, sleep, or
                // interruption). Scheduled segments are cleared when the
                // engine stops, so a plain play() would be silent — restart
                // and reschedule the current track from the saved position.
                resumePlaybackAfterInterruption()
                return
            }
            playerNode.play()
            isPlaying = true
            lastTickTimestamp = Date()
        }
    }

    func stop() {
        fileLog("STOP — playSessionID was \(playSessionID)")
        playSessionID = UUID()
        shouldStopAfterCurrentTrack = false
        stopProgressUpdates()
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        engine = nil
        eq = nil
        audioFiles = []
        tracks = []
        currentTrackIndex = -1
        accumulatedPlayTime = 0
        isPlaying = false
        currentProgress = 0
        fileLog("STOP complete")
    }

    // MARK: - EQ

    func applyEQ(preset: EQPreset) {
        pendingEQPreset = preset
        eq?.apply(preset: preset)
        fileLog("Applied EQ preset: \(preset.name)")
    }

    var currentEQPreset: EQPreset {
        eq?.currentPreset ?? pendingEQPreset ?? .flat
    }

    // MARK: - Progress

    private var currentTrackDuration: TimeInterval {
        guard currentTrackIndex >= 0, currentTrackIndex < audioFiles.count else { return 0 }
        let file = audioFiles[currentTrackIndex]
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private func startProgressUpdates() {
        stopProgressUpdates()
        accumulatedPlayTime = 0
        lastTickTimestamp = Date()
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
        lastTickTimestamp = nil
    }

    private func refreshProgress() {
        let duration = currentTrackDuration
        guard duration > 0 else {
            currentProgress = 0
            return
        }
        if let last = lastTickTimestamp {
            accumulatedPlayTime += Date().timeIntervalSince(last)
            lastTickTimestamp = Date()
        }
        currentProgress = min(1.0, max(0, accumulatedPlayTime / duration))
    }
}
