# Playdoro

macOS menu-bar app / iOS app — Pomodoro timer synced with Plex music playback.

## Build & Test

- `swift build` — build (macOS)
- `swift test` — run all tests (XCTest, 36 cases across 7 suites)
- **iOS simulator:** `xcodebuild -project iOSApp/Playdoro.xcodeproj -scheme Playdoro -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.1" build`
- **iOS device:** build then install/launch via `devicectl`:
  ```bash
  xcodebuild -project iOSApp/Playdoro.xcodeproj -scheme Playdoro \
    -destination "platform=iOS,id=<devicectl-id>" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM=<your-team-id> build
  APP=~/Library/Developer/Xcode/DerivedData/Playdoro-*/Build/Products/Debug-iphoneos/Playdoro.app
  xcrun devicectl device install app --device <devicectl-id> "$APP"
  xcrun devicectl device process launch --device <devicectl-id> <bundle-id>
  ```
  - List devices: `xcrun devicectl list devices` (gives the `devicectl-id`).
  - The development team is set via `DEVELOPMENT_TEAM` in the pbxproj build settings (Debug + Release); override on the CLI or in the Xcode GUI as needed.
  - **Signing/cert errors** ("profile doesn't include certificate", "device isn't registered"): resolve in the **Xcode GUI** — open the project, target → Signing & Capabilities → Automatic + select the team. Xcode regenerates the dev cert and registers the connected device where `xcodebuild -allowProvisioningUpdates` alone won't. Keep the device unlocked.
- No lint, formatter, or CI configured.
- SPM package at repo root produces two products: the `Playdoro` macOS executable and the `PlaydoroKit` library (linked by both the macOS executable and the iOS Xcode project). The iOS app lives in a separate `iOSApp/Playdoro.xcodeproj` (`DerivedData/` gitignored).

## Dependencies

- **swift-log** — structured logging (Apple ecosystem stdlib). 
- No other external deps — Apple SDKs only (SwiftUI, AVFoundation, Combine, OSLog, XCTest).

## Architecture

- **Entrypoint:** `Sources/PlaydoroKit/PlaydoroApp.swift` — `@main` SwiftUI `App` with `MenuBarExtra(.window)` (macOS) or `WindowGroup` (iOS). Both apps (`Sources/Playdoro/main.swift` and `iOSApp/Playdoro/main.swift`) just call `PlaydoroApp.main()` from PlaydoroKit.
- **State:** `AppState` (`@MainActor`, `ObservableObject`) — owns `MusicProvider` + `AudioPlayer` directly
- **Protocol:** `MusicProvider: Sendable` — abstracts music search, playback URLs, session (provider-agnostic; other backends could be added)
- **Networking (Plex):** `PlexClient` (`actor`, conforms `MusicProvider`) — Plex HTTP API with self-signed cert support via `CertDelegate`
- **Audio:** `AudioPlayer` (`@MainActor`) — wraps `AVAudioEngine` + `AVAudioPlayerNode`, downloads tracks via `TrackCache` before playback. On iOS, handles `AVAudioSession` interruptions and `AVAudioEngine` configuration changes so playback survives screen lock, sleep, and audio route swaps.
- **EQ:** `AudioEQ` — manages `AVAudioUnitEQ`, applies AutoEQ presets, supports hard-bypass toggle that remembers the selected preset. Catalog of ~880 presets from oratory1990 + Kazi is bundled as text resources and parsed at startup by `EQPresetLoader`.
- **Cache:** `TrackCache` (`actor`) — bounded on-disk LRU cache for downloaded audio files (default 500 MB)
- **Engine:** `PomodoroEngine` (value-type struct) — two-phase pack algorithm (lookahead random → greedy fill)

### Modularisation Direction

Music provider is a protocol so the backend is swappable:
- `MusicProvider` protocol (search, getTrack, getNearest, getStreamURL)
- `PlexClient` conforms
- `AppState` references `MusicProvider` instead of `PlexClient`
- `Track` is already generic (id, title, artist, album, duration, score) — `PomodoroEngine` and `AudioPlayer` are already provider-agnostic

## Key Files

| File | Role |
|------|------|
| `PlaydoroApp.swift` | Entrypoint — `@main` App struct only (macOS MenuBarExtra / iOS WindowGroup) |
| `ContentView.swift` | Root content router (idle, active, settings, connection states) |
| `ActiveSessionView.swift` | Running pomodoro view (timer, album art, playlist, volume slider, controls) |
| `PlaylistView.swift` | Track list during active session |
| `SearchBar.swift` | Seed-track search with results list |
| `ConnectView.swift`, `LinkingView.swift`, `DiscoveringView.swift`, `FailedView.swift` | OAuth connection flow views |
| `SettingsView.swift` | Connection info, EQ toggle + preset picker entry, disconnect |
| `EQPickerView.swift` | Searchable list of bundled EQ presets, filterable by author |
| `AppState.swift` | ViewModel — timer, playlist, orchestrates PlexClient + AudioPlayer |
| `PlexClient.swift` | Actor-based Plex API client (search, nearest, sessions, stream URLs) conforming `MusicProvider` |
| `MusicProvider.swift` | `MusicProvider` protocol — abstracts search, playback URLs, session |
| `AudioPlayer.swift` | AVAudioEngine wrapper, sequential download + cleanup |
| `AudioEQ.swift` | Manages `AVAudioUnitEQ`, hard-bypass toggle, AutoEQ preset loader + parser |
| `Resources/EQPresets/<author>/<category>/<headphone>.txt` | 879 AutoEQ `ParametricEQ.txt` files (oratory1990 736 + Kazi 143), upstream `jaakkopasanen/AutoEq@7ae0f56` (2025-07-20). Bundled via `.copy("Resources/EQPresets")` in `Package.swift`; reachable through `Bundle.module` in both macOS + iOS apps. |
| `TrackCache.swift` | Bounded on-disk LRU cache for downloaded audio files |
| `PomodoroEngine.swift` | Track-packing algorithm (lookahead random + greedy fill) |
| `Models.swift` | Track, JSON decoding types (CodingKeys), errors |
| `AlbumArt.swift` | Async album art via URLSession + CertDelegate |
| `CertDelegate.swift` | Trusts all server certs (self-signed Plex on LAN) |
| `Tests/PlaydoroTests/PomodoroEngineTests.swift` | 3 test classes, 16 cases (PomodoroEngineTests, DeduplicateTests, ErrorDescriptionTests) |
| `Tests/PlaydoroTests/TrackCacheTests.swift` | Cache store/retrieve, eviction, and LRU ordering tests |
| `Tests/PlaydoroTests/EQPresetTests.swift` | 17 cases — AutoEQ parser, legacy ID migration, catalog sanity |

## Quirks & Gotchas

- `Info.plist` is excluded from SPM build (`exclude: ["Info.plist"]` in Package.swift) but still present in Sources
- `NSAppTransportSecurity` allows local networking — needed for self-signed Plex certs on LAN
- `CertDelegate` relaxes validation only for LAN/private hosts and pins the server's public key on first use (TOFU); public hosts get normal validation
- Plex JSON response shape: `MediaContainer` → `Metadata[]` — unwrapped via `CodingKeys`
- Track durations are in **milliseconds** everywhere (`duration / 1000` to get seconds)
- Tracks download sequentially to a bounded on-disk cache before `AVAudioEngine` starts; cache persists across sessions
- Audio log at `<tmp>/playdoro_audio_player.log` (OSLog + file)
- Git workflow: features land on `main` (see iOS SPM note below for why `main` matters)
- **iOS Xcode project + SPM:** the iOS app references the local package by `file://` URL with `branch = main`. SPM does a real git checkout, so **working-tree changes to `Sources/PlaydoroKit/*` are not seen by the iOS build until committed**. `PlaydoroKit` must remain declared as a `.library` product in `Package.swift` (not just a target) or the iOS app fails with "Missing package product 'PlaydoroKit'".
- **iOS builds read `PlaydoroKit` from `main`:** because the iOS package ref is pinned to `branch = main`, `PlaydoroKit` changes must land **on `main`** before the iOS build can see them — a feature branch alone won't do. If your workflow blocks direct commits to `main`, commit on a throwaway branch then fast-forward `main` (the FF is a `git switch`/`git merge`, not a `git commit`):
  ```bash
  git switch -c feat/<desc>
  git commit -m "…"
  git switch main
  git merge --ff-only feat/<desc>         # lands commit on main, no new commit
  git branch -d feat/<desc>
  ```
- **iOS SPM pin stickiness (important):** even after committing, SPM with `branch = main` on a local package does **not** auto-bump to new commits on rebuild — it stays pinned to whatever revision was first resolved (recorded in `iOSApp/Playdoro.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`). `xcodebuild build` and `xcodebuild -resolvePackageDependencies` both happily re-use the stale pin. To force the iOS build to pick up a new commit in `PlaydoroKit`, nuke the project's DerivedData entirely:
  ```bash
  rm -rf ~/Library/Developer/Xcode/DerivedData/Playdoro-*
  rm -f iOSApp/Playdoro.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
  xcodebuild -project iOSApp/Playdoro.xcodeproj -scheme Playdoro -destination "platform=iOS Simulator,name=iPhone 16 Pro,OS=18.1" build
  ```
  Deleting `Package.resolved` alone is NOT enough — Xcode regenerates it from cached state. Verify the right commit was used by checking the built binary: `strings <app>/Playdoro.debug.dylib | grep '<some-new-string>'`. Symptom of stale pin: iOS runtime behaviour doesn't match what you see in `Sources/PlaydoroKit/*` on disk.
- **iOS Xcode project paths:** all source/asset files live in `iOSApp/Playdoro/` (not `iOSApp/Sources/`). The pbxproj group `path = Playdoro`, `INFOPLIST_FILE = Playdoro/Info.plist`, and `Assets.xcassets` fileRef path is `Playdoro/Assets.xcassets` — keep these consistent if rearranging files.
- **iOS background audio:** screen locks normally during playback (no idle-timer wake lock). Audio continues in the background via `UIBackgroundModes: audio` (`iOSApp/Playdoro/Info.plist`) + `AVAudioSession.setCategory(.playback)` (in `AudioPlayer.configureAudioSession`). `AudioPlayer` also observes `AVAudioSession.interruptionNotification` and `.AVAudioEngineConfigurationChange` to reschedule the current track from `accumulatedPlayTime` after interruptions/route swaps.
