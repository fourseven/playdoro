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

        for track in sorted {
            let newTotal = total + track.duration / 1000
            if newTotal <= maxDuration {
                selected.append(track)
                total = newTotal
            }
            if total >= minDuration && total <= maxDuration {
                break
            }
        }

        if total < minDuration && !sorted.isEmpty {
            selected.append(sorted.last!)
            total += sorted.last!.duration / 1000
        }

        return selected
    }

    func totalDuration(of tracks: [PlexTrack]) -> TimeInterval {
        tracks.reduce(0) { $0 + $1.duration / 1000 }
    }
}
