import AVFoundation
import Foundation

/// Platform-agnostic EQ filter shape.
enum EQFilterType: Equatable, Hashable {
    case parametric
    case lowShelf
    case highShelf
}

/// Parametric EQ band definition.
struct EQBand: Equatable, Hashable, Identifiable {
    let id = UUID()
    var frequency: Float
    var gain: Float
    var q: Float
    var filterType: EQFilterType
}

/// A named EQ preset that can be applied to the audio engine.
struct EQPreset: Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let bands: [EQBand]
    let preamp: Float
}

extension EQPreset {
    /// Flat / bypass EQ. Used as the default.
    static let flat = EQPreset(
        id: "flat",
        name: "Flat",
        bands: [],
        preamp: 0
    )

    /// Sennheiser HD 6XX correction from the oratory1990 over-ear target
    /// (AutoEQ project). Filter labels LSC/HSC map to lowShelf/highShelf.
    static let hd6xx = EQPreset(
        id: "hd6xx",
        name: "HD 6XX",
        bands: [
            EQBand(frequency: 105, gain: 6.4, q: 0.70, filterType: .lowShelf),
            EQBand(frequency: 118, gain: -3.1, q: 0.50, filterType: .parametric),
            EQBand(frequency: 37, gain: 0.7, q: 3.96, filterType: .parametric),
            EQBand(frequency: 587, gain: 0.4, q: 1.19, filterType: .parametric),
            EQBand(frequency: 1227, gain: -1.2, q: 2.53, filterType: .parametric),
            EQBand(frequency: 2055, gain: 1.2, q: 3.23, filterType: .parametric),
            EQBand(frequency: 3169, gain: -1.7, q: 3.89, filterType: .parametric),
            EQBand(frequency: 5332, gain: -1.1, q: 5.75, filterType: .parametric),
            EQBand(frequency: 8800, gain: 5.1, q: 1.42, filterType: .parametric),
            EQBand(frequency: 10000, gain: -2.1, q: 0.70, filterType: .highShelf)
        ],
        preamp: -6.1
    )

    /// Slightly emphasised low end for speakers/headphones that sound thin.
    static let warm = EQPreset(
        id: "warm",
        name: "Warm",
        bands: [
            EQBand(frequency: 120, gain: 3.5, q: 0.71, filterType: .lowShelf),
            EQBand(frequency: 3000, gain: -1.5, q: 1.0, filterType: .parametric),
            EQBand(frequency: 8000, gain: -2.0, q: 0.71, filterType: .highShelf)
        ],
        preamp: -3.5
    )

    /// Brighter, more present upper-mids for detail.
    static let bright = EQPreset(
        id: "bright",
        name: "Bright",
        bands: [
            EQBand(frequency: 80, gain: -2.0, q: 0.71, filterType: .lowShelf),
            EQBand(frequency: 2500, gain: 2.0, q: 1.2, filterType: .parametric),
            EQBand(frequency: 6000, gain: 1.5, q: 1.5, filterType: .parametric),
            EQBand(frequency: 11000, gain: 2.5, q: 0.71, filterType: .highShelf)
        ],
        preamp: -4.0
    )

    static let all: [EQPreset] = [.flat, .hd6xx, .warm, .bright]

    /// Presets shown in the settings UI: Off (Flat) and HD 6XX.
    static let settingsPresets: [EQPreset] = [.flat, .hd6xx]
}

/// Manages the AVAudioUnitEQ node and applies presets.
@MainActor
final class AudioEQ {
    let eqNode = AVAudioUnitEQ(numberOfBands: 10)

    private(set) var currentPreset: EQPreset = .flat

    init() {
        eqNode.bypass = true
        apply(preset: .flat)
    }

    func apply(preset: EQPreset) {
        currentPreset = preset

        let activeBands = Array(preset.bands.prefix(eqNode.bands.count))

        for (index, band) in activeBands.enumerated() {
            let nodeBand = eqNode.bands[index]
            nodeBand.filterType = band.avFilterType
            nodeBand.frequency = band.frequency
            nodeBand.gain = band.gain
            nodeBand.bypass = false
            // AVAudioUnitEQ uses bandwidth (octaves) rather than Q.
            nodeBand.bandwidth = band.bandwidth
        }

        for index in activeBands.count..<eqNode.bands.count {
            eqNode.bands[index].bypass = true
            eqNode.bands[index].gain = 0
        }

        eqNode.globalGain = preset.preamp
        eqNode.bypass = preset.bands.isEmpty
    }
}

private extension EQBand {
    /// Convert Q to the bandwidth in octaves used by AVAudioUnitEQ.
    var bandwidth: Float {
        // Octave bandwidth ≈ log2(fc / bwHz) where bwHz = fc / Q
        // Simplified: bandwidthOctaves = log2(Q) is not correct.
        // Use the standard relationship: BW_octaves = 2 / ln(2) * asinh(1 / (2 * Q))
        let inv2Q = 1.0 / (2.0 * q)
        return (2.0 / log(2.0)) * asinh(inv2Q)
    }

    var avFilterType: AVAudioUnitEQFilterType {
        switch filterType {
        case .parametric:
            return .parametric
        case .lowShelf:
            return .lowShelf
        case .highShelf:
            return .highShelf
        }
    }
}
