# Plexodoro

macOS menu-bar app / iOS app — Pomodoro timer synced with Plex music playback (Spotify support planned).

## Build & Test

- `swift build` — build (macOS)
- `swift test` — run all tests (XCTest, 36 cases across 7 suites)
- **iOS simulator:** `xcodebuild -project iOSApp/Plexodoro.xcodeproj -scheme Plexodoro -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.1" build`
- **iOS device:** build then install/launch via `devicectl`:
  ```bash
  xcodebuild -project iOSApp/Plexodoro.xcodeproj -scheme Plexodoro \
    -destination "platform=iOS,id=<devicectl-id>" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM=88X59PVX4X build
  APP=~/Library/Developer/Xcode/DerivedData/Plexodoro-*/Build/Products/Debug-iphoneos/Plexodoro.app
  xcrun devicectl device install app --device <devicectl-id> "$APP"
  xcrun devicectl device process launch --device <devicectl-id> com.mathewhartley.plexodoro
  ```
  - List devices: `xcrun devicectl list devices`. Current test phone "Mathew's iPhone" (iPhone 12 Pro): devicectl-id `00000000-0000-0000-0000-000000000000`, UDID `00000000-0000000000000000`.
  - Apple Developer team `88X59PVX4X` (Individual, Mathew Hartley). `DEVELOPMENT_TEAM` is **not** in pbxproj — pass it on the CLI.
  - **Signing/cert errors** ("profile doesn't include certificate", "device isn't registered"): resolve in the **Xcode GUI** — open the project, target → Signing & Capabilities → Automatic + select the team. Xcode regenerates the dev cert and registers the connected device where `xcodebuild -allowProvisioningUpdates` alone won't. Keep the iPhone unlocked.
- No lint, formatter, or CI configured.
- SPM package at repo root produces two products: the `Plexodoro` macOS executable and the `PlexodoroKit` library (linked by both the macOS executable and the iOS Xcode project). The iOS app lives in a separate `iOSApp/Plexodoro.xcodeproj` (`DerivedData/` gitignored).

## Dependencies

- **swift-log** — structured logging (Apple ecosystem stdlib). 
- No other external deps — Apple SDKs only (SwiftUI, AVFoundation, Combine, OSLog, XCTest).

## Architecture

- **Entrypoint:** `Sources/PlexodoroKit/PlexodoroApp.swift` — `@main` SwiftUI `App` with `MenuBarExtra(.window)` (macOS) or `WindowGroup` (iOS). Both apps (`Sources/Plexodoro/main.swift` and `iOSApp/Plexodoro/main.swift`) just call `PlexodoroApp.main()` from PlexodoroKit.
- **State:** `AppState` (`@MainActor`, `ObservableObject`) — owns `MusicProvider` + `AudioPlayer` directly
- **Protocol:** `MusicProvider: Sendable` — abstracts music search, playback URLs, session (Plex/Spotify interchangeable)
- **Networking (Plex):** `PlexClient` (`actor`, conforms `MusicProvider`) — Plex HTTP API with self-signed cert support via `CertDelegate`
- **Audio:** `AudioPlayer` (`@MainActor`) — wraps `AVAudioEngine` + `AVAudioPlayerNode`, downloads tracks via `TrackCache` before playback. On iOS, handles `AVAudioSession` interruptions and `AVAudioEngine` configuration changes so playback survives screen lock, sleep, and audio route swaps.
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
- **iOS Xcode project + SPM:** the iOS app references the local package by `file://` URL with `branch = main`. SPM does a real git checkout, so **working-tree changes to `Sources/PlexodoroKit/*` are not seen by the iOS build until committed**. `PlexodoroKit` must remain declared as a `.library` product in `Package.swift` (not just a target) or the iOS app fails with "Missing package product 'PlexodoroKit'".
- **iOS SPM pin stickiness (important):** even after committing, SPM with `branch = main` on a local package does **not** auto-bump to new commits on rebuild — it stays pinned to whatever revision was first resolved (recorded in `iOSApp/Plexodoro.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`). `xcodebuild build` and `xcodebuild -resolvePackageDependencies` both happily re-use the stale pin. To force the iOS build to pick up a new commit in `PlexodoroKit`, nuke the project's DerivedData entirely:
  ```bash
  rm -rf ~/Library/Developer/Xcode/DerivedData/Plexodoro-*
  rm -f iOSApp/Plexodoro.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
  xcodebuild -project iOSApp/Plexodoro.xcodeproj -scheme Plexodoro -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.1" build
  ```
  Deleting `Package.resolved` alone is NOT enough — Xcode regenerates it from cached state. Verify the right commit was used by checking the built binary: `strings <app>/Plexodoro.debug.dylib | grep '<some-new-string>'`. Symptom of stale pin: iOS runtime behaviour doesn't match what you see in `Sources/PlexodoroKit/*` on disk.
- **iOS Xcode project paths:** all source/asset files live in `iOSApp/Plexodoro/` (not `iOSApp/Sources/`). The pbxproj group `path = Plexodoro`, `INFOPLIST_FILE = Plexodoro/Info.plist`, and `Assets.xcassets` fileRef path is `Plexodoro/Assets.xcassets` — keep these consistent if rearranging files.
- **iOS background audio:** screen locks normally during playback (no idle-timer wake lock). Audio continues in the background via `UIBackgroundModes: audio` (`iOSApp/Plexodoro/Info.plist`) + `AVAudioSession.setCategory(.playback)` (in `AudioPlayer.configureAudioSession`). `AudioPlayer` also observes `AVAudioSession.interruptionNotification` and `.AVAudioEngineConfigurationChange` to reschedule the current track from `accumulatedPlayTime` after interruptions/route swaps.
