import Foundation

struct PomodoroEngine {
    let config: PomodoroConfig

    init(config: PomodoroConfig = .default) {
        self.config = config
    }

    func pack(tracks: [PlexTrack], target: TimeInterval? = nil) -> [PlexTrack] {
        let target = target ?? config.targetDuration
        let minDuration = target - config.tolerance
        let maxDuration = target + config.tolerance

        let sorted = tracks.sorted { a, b in
            (a.distance ?? Double.infinity) < (b.distance ?? Double.infinity)
        }

        var selected: [PlexTrack] = []
        var total: TimeInterval = 0
        var i = 0

        while i < sorted.count, total < minDuration {
            // Look at the next few candidates and pick one randomly
            let lookaheadEnd = min(i + 3, sorted.count)
            let candidates = sorted[i..<lookaheadEnd].filter {
                total + $0.duration / 1000 <= maxDuration
            }

            if let pick = candidates.randomElement() {
                selected.append(pick)
                total += pick.duration / 1000
                // Move past the picked track
                while i < sorted.count, sorted[i] != pick { i += 1 }
                i += 1
            } else {
                i += 1
            }
        }

        // Still short? greedily add whatever fits
        if total < minDuration {
            for track in sorted where !selected.contains(track) {
                let newTotal = total + track.duration / 1000
                if newTotal <= maxDuration {
                    selected.append(track)
                    total = newTotal
                }
                if total >= minDuration { break }
            }
        }

        return selected
    }

    func totalDuration(of tracks: [PlexTrack]) -> TimeInterval {
        tracks.reduce(0) { $0 + $1.duration / 1000 }
    }
}
