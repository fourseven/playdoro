import Foundation

struct PomodoroEngine {
    let config: PomodoroConfig

    init(config: PomodoroConfig = .default) {
        self.config = config
    }

    func pack(tracks: [Track], target: TimeInterval? = nil) -> [Track] {
        let target = target ?? config.targetDuration
        let minDuration = target - config.tolerance
        let maxDuration = target + config.tolerance

        let sorted = tracks.sorted { a, b in
            (a.score ?? Double.infinity) < (b.score ?? Double.infinity)
        }

        var (selected, total, _) = fillLookahead(from: sorted, minDuration: minDuration, maxDuration: maxDuration)

        if total < minDuration {
            (selected, total) = fillGreedy(from: sorted, excluding: selected, total: total, minDuration: minDuration, maxDuration: maxDuration)
        }

        return selected
    }

    func totalDuration(of tracks: [Track]) -> TimeInterval {
        tracks.reduce(0) { $0 + $1.duration / 1000 }
    }

    private func fillLookahead(from sorted: [Track], minDuration: TimeInterval, maxDuration: TimeInterval) -> (selected: [Track], total: TimeInterval, index: Int) {
        var selected: [Track] = []
        var total: TimeInterval = 0
        var i = 0

        while i < sorted.count, total < minDuration {
            let lookaheadEnd = min(i + 3, sorted.count)
            let candidates = sorted[i..<lookaheadEnd].filter {
                total + $0.duration / 1000 <= maxDuration
            }

            if let pick = candidates.randomElement() {
                selected.append(pick)
                total += pick.duration / 1000
                while i < sorted.count, sorted[i] != pick { i += 1 }
                i += 1
            } else {
                i += 1
            }
        }

        return (selected, total, i)
    }

    private func fillGreedy(from sorted: [Track], excluding selected: [Track], total: TimeInterval, minDuration: TimeInterval, maxDuration: TimeInterval) -> (selected: [Track], total: TimeInterval) {
        var selected = selected
        var total = total

        for track in sorted where !selected.contains(track) {
            let newTotal = total + track.duration / 1000
            if newTotal <= maxDuration {
                selected.append(track)
                total = newTotal
            }
            if total >= minDuration { break }
        }

        return (selected, total)
    }
}
