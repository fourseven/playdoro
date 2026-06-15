# Plexodoro

macOS menu-bar app / iOS app — Pomodoro timer synced with Plex music playback (Spotify support planned).

## Build & Test

- `swift build` — build (macOS)
- `swift test` — run all tests (XCTest, 36 cases across 7 suites)
- **iOS:** `xcodebuild -scheme Plexodoro -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.1" build`
- **Device:** `xcodebuild -scheme Plexodoro -destination "platform=iOS,name=<device>" build -allowProvisioningUpdates`
- No lint, formatter, or CI configured.
- Single SPM package, no Xcode project (SPM generates one; `DerivedData/` gitignored).

## Dependencies

- **swift-log** — structured logging (Apple ecosystem stdlib). 
- No other external deps — Apple SDKs only (SwiftUI, AVFoundation, Combine, OSLog, XCTest).

## Architecture

- **Entrypoint:** `Sources/Plexodoro/PlexodoroApp.swift` — `@main` SwiftUI `App` with `MenuBarExtra(.window)` (macOS) or `WindowGroup` (iOS)
- **State:** `AppState` (`@MainActor`, `ObservableObject`) — owns `MusicProvider` + `AudioPlayer` directly
- **Protocol:** `MusicProvider: Sendable` — abstracts music search, playback URLs, session (Plex/Spotify interchangeable)
- **Networking (Plex):** `PlexClient` (`actor`, conforms `MusicProvider`) — Plex HTTP API with self-signed cert support via `CertDelegate`
- **Audio:** `AudioPlayer` (`@MainActor`) — wraps `AVAudioEngine` + `AVAudioPlayerNode`, downloads tracks via `TrackCache` before playback
- **EQ:** `AudioEQ` — manages `AVAudioUnitEQ` and named presets (Flat, HD 6XX, Warm, Bright)
- **Cache:** `TrackCache` (`actor`) — bounded on-disk LRU cache for downloaded audio files (default 500 MB)
- **Engine:** `PomodoroEngine` (value-type struct) — two-phase pack algorithm (lookahead random → greedy fill)

### Modularisation Direction

Music provider is now a protocol so Plex/Spotify are interchangeable:
- `MusicProvider` protocol (search, getTrack, getNearest, getStreamURL)
- `PlexClient` conforms; `SpotifyClient` is new conformance
- `AppState` references `MusicProvider` instead of `PlexClient`
- `Track` is already generic (id, title, artist, album, duration, score) — `PomodoroEngine` and `AudioPlayer` are already provider-agnostic

## Key Files

| File | Role |
|------|------|
| `PlexodoroApp.swift` | Entrypoint — `@main` App struct only (macOS MenuBarExtra / iOS WindowGroup) |
| `ContentView.swift` | Root content router (idle, active, settings, connection states) |
| `ActiveSessionView.swift` | Running pomodoro view (timer, album art, playlist, volume slider, controls) |
| `PlaylistView.swift` | Track list during active session |
| `SearchBar.swift` | Seed-track search with results list |
| `ConnectView.swift`, `LinkingView.swift`, `DiscoveringView.swift`, `FailedView.swift` | OAuth connection flow views |
| `SettingsView.swift` | Connection info, EQ preset picker, disconnect |
| `AppState.swift` | ViewModel — timer, playlist, orchestrates PlexClient + AudioPlayer |
| `PlexClient.swift` | Actor-based Plex API client (search, nearest, sessions, stream URLs) conforming `MusicProvider` |
| `MusicProvider.swift` | `MusicProvider` protocol — abstracts search, playback URLs, session |
| `AudioPlayer.swift` | AVAudioEngine wrapper, sequential download + cleanup |
| `AudioEQ.swift` | Manages `AVAudioUnitEQ` and named presets |
| `TrackCache.swift` | Bounded on-disk LRU cache for downloaded audio files |
| `PomodoroEngine.swift` | Track-packing algorithm (lookahead random + greedy fill) |
| `Models.swift` | Track, JSON decoding types (CodingKeys), errors |
| `AlbumArt.swift` | Async album art via URLSession + CertDelegate |
| `CertDelegate.swift` | Trusts all server certs (self-signed Plex on LAN) |
| `Tests/PlexodoroTests/PomodoroEngineTests.swift` | 3 test classes, 16 cases (PomodoroEngineTests, DeduplicateTests, ErrorDescriptionTests) |
| `Tests/PlexodoroTests/TrackCacheTests.swift` | Cache store/retrieve, eviction, and LRU ordering tests |

## Quirks & Gotchas

- `Info.plist` is excluded from SPM build (`exclude: ["Info.plist"]` in Package.swift) but still present in Sources
- `NSAppTransportSecurity` allows local networking — needed for self-signed Plex certs on LAN
- `CertDelegate` trusts every server trust — safe only for LAN use
- Plex JSON response shape: `MediaContainer` → `Metadata[]` — unwrapped via `CodingKeys`
- Track durations are in **milliseconds** everywhere (`duration / 1000` to get seconds)
- Tracks download sequentially to a bounded on-disk cache before `AVAudioEngine` starts; cache persists across sessions
- Audio log at `<tmp>/plexodoro_audio_player.log` (OSLog + file)
- No git remotes — local-only repo
