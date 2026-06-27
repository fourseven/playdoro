import Foundation

/// Selection weight for a candidate track given its normalized distance from
/// its seed (`score`, 0 = closest, nil = unknown) and the user's variety
/// preference (0 = strict/always-nearest, 1 = uniform/random). Higher weight =
/// more likely to be picked. At `variety >= 1` every track weighs equally
/// (uniform); at `variety == 0` the closest track dominates sharply. Pure so
/// it can be unit-tested without the engine.
func selectionWeight(score: Double?, variety: Double) -> Double {
    let v = min(max(variety, 0), 1)
    if v >= 1 { return 1 }
    let s = score ?? 1.0
    let strictness = (1 - v) * 14
    return pow(max(0, 1 - s), strictness)
}

struct PomodoroEngine {
    let config: PomodoroConfig

    init(config: PomodoroConfig = .default) {
        self.config = config
    }

    func pack(tracks: [Track], target: TimeInterval? = nil) -> [Track] {
        let target = target ?? config.targetDuration
        let minDuration = target - config.tolerance
        let maxDuration = target + config.tolerance

        // Respect caller-supplied order. For multi-seed runs the caller
        // (`MusicProvider.getNearest(trackIds:)`) interleaves batches
        // round-robin so this walk rotates across seeds; sorting globally by
        // raw per-seed distance here would re-introduce the cross-seed bias
        // (the tightest cluster floods the front of the sort).
        let ordered = tracks

        var (selected, total, _) = fillLookahead(from: ordered, minDuration: minDuration, maxDuration: maxDuration)

        if total < minDuration {
            (selected, total) = fillGreedy(from: ordered, excluding: selected, total: total, minDuration: minDuration, maxDuration: maxDuration)
        }

        return selected
    }

    /// Pack tracks around a set of must-include seeds. Seed duration is reserved from the
    /// target before packing so the final playlist (packed + seeds) stays within tolerance.
    /// Seeds are appended in caller-supplied order; caller is responsible for shuffling.
    func pack(tracks: [Track], mustInclude: [Track], target: TimeInterval? = nil) -> [Track] {
        let target = target ?? config.targetDuration
        let seedDuration = mustInclude.reduce(0) { $0 + $1.duration / 1000 }
        let seedIds = Set(mustInclude.map(\.id))
        let candidates = tracks.filter { !seedIds.contains($0.id) }
        let adjustedTarget = max(target - seedDuration, config.tolerance)
        let packed = pack(tracks: candidates, target: adjustedTarget)
        return packed + mustInclude
    }

    func totalDuration(of tracks: [Track]) -> TimeInterval {
        tracks.reduce(0) { $0 + $1.duration / 1000 }
    }

    private func fillLookahead(from ordered: [Track], minDuration: TimeInterval, maxDuration: TimeInterval) -> (selected: [Track], total: TimeInterval, index: Int) {
        var selected: [Track] = []
        var total: TimeInterval = 0
        var i = 0

        while i < ordered.count, total < minDuration {
            let lookaheadEnd = min(i + 3, ordered.count)
            let candidates = ordered[i..<lookaheadEnd].filter {
                total + $0.duration / 1000 <= maxDuration
            }

            if let pick = weightedPick(Array(candidates)) {
                selected.append(pick)
                total += pick.duration / 1000
                while i < ordered.count, ordered[i] != pick { i += 1 }
                i += 1
            } else {
                i += 1
            }
        }

        return (selected, total, i)
    }

    /// Weighted random pick over a non-empty candidate slice using
    /// `selectionWeight` driven by `config.variety`. Falls back to uniform
    /// random when all weights collapse to zero (e.g. every candidate is the
    /// farthest and variety is 0).
    private func weightedPick(_ tracks: [Track]) -> Track? {
        guard let first = tracks.first else { return nil }
        if tracks.count == 1 { return first }
        let weights = tracks.map { selectionWeight(score: $0.score, variety: config.variety) }
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return tracks.randomElement() }
        var r = Double.random(in: 0..<sum)
        for (track, weight) in zip(tracks, weights) {
            r -= weight
            if r < 0 { return track }
        }
        return tracks.last
    }

    private func fillGreedy(from ordered: [Track], excluding selected: [Track], total: TimeInterval, minDuration: TimeInterval, maxDuration: TimeInterval) -> (selected: [Track], total: TimeInterval) {
        var selected = selected
        var total = total

        for track in ordered where !selected.contains(track) {
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
