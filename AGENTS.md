# Plexodoro

macOS menu-bar app — Pomodoro timer synced with Plex music playback (Spotify support planned).

## Build & Test

- `swift build` — build
- `swift test` — run all tests (XCTest, 16 cases across 3 suites)
- No lint, formatter, or CI configured.
- Single SPM package, no Xcode project (SPM generates one; `DerivedData/` gitignored).

## Dependencies

- **RxSwift** — reactive framework of choice (added via SPM). Existing code still uses **Combine** (to be migrated gradually).
- No other external deps — Apple SDKs only (SwiftUI, AVFoundation, Combine, OSLog, XCTest).

## Architecture

- **Entrypoint:** `Sources/Plexodoro/PlexodoroApp.swift` — `@main` SwiftUI `App` with `MenuBarExtra(.window)`
- **State:** `AppState` (`@MainActor`, `ObservableObject`) — owns `MusicProvider` + `AudioPlayer` directly
- **Protocol:** `MusicProvider: Sendable` — abstracts music search, playback URLs, session (Plex/Spotify interchangeable)
- **Networking (Plex):** `PlexClient` (`actor`, conforms `MusicProvider`) — Plex HTTP API with self-signed cert support via `CertDelegate`
- **Audio:** `AudioPlayer` (`@MainActor`) — wraps `AVQueuePlayer`, downloads all tracks to temp files before playback
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
| `PlexodoroApp.swift` | Entrypoint, all SwiftUI views (ContentView, ActiveSessionView, SettingsView) |
| `AppState.swift` | ViewModel — timer, playlist, orchestrates PlexClient + AudioPlayer |
| `PlexClient.swift` | Actor-based Plex API client (search, nearest, sessions, stream URLs) conforming `MusicProvider` |
| `MusicProvider.swift` | `MusicProvider` protocol — abstracts search, playback URLs, session |
| `AudioPlayer.swift` | AVQueuePlayer wrapper, sequential download + cleanup |
| `PomodoroEngine.swift` | Track-packing algorithm |
| `Models.swift` | Track, JSON decoding types (CodingKeys), errors |
| `AlbumArt.swift` | Async album art via URLSession + CertDelegate |
| `CertDelegate.swift` | Trusts all server certs (self-signed Plex on LAN) |
| `Tests/PlexodoroTests/PomodoroEngineTests.swift` | 3 test classes, 16 cases (PomodoroEngineTests, DeduplicateTests, ErrorDescriptionTests) |

## Quirks & Gotchas

- `Info.plist` is excluded from SPM build (`exclude: ["Info.plist"]` in Package.swift) but still present in Sources
- `NSAppTransportSecurity` allows local networking — needed for self-signed Plex certs on LAN
- `CertDelegate` trusts every server trust — safe only for LAN use
- Plex JSON response shape: `MediaContainer` → `Metadata[]` — unwrapped via `CodingKeys`
- Track durations are in **milliseconds** everywhere (`duration / 1000` to get seconds)
- Tracks download sequentially to temp files before `AVQueuePlayer` starts; cleaned up on `stop()`
- Audio log at `<tmp>/plexodoro_audio_player.log` (OSLog + file)
- No git remotes — local-only repo
