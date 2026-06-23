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
///
/// `author` and `category` describe the source (e.g. author "oratory1990",
/// category "over-ear") so the picker UI can group and filter presets. The
/// `id` is the stable string `"<author>/<category>/<name>"` used for
/// persistence in UserDefaults.
struct EQPreset: Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var author: String
    var category: String
    var bands: [EQBand]
    var preamp: Float
}

extension EQPreset {
    /// Flat / bypass EQ. Used as the default. Not loaded from disk — there is
    /// no Flat headphone in the AutoEQ dataset.
    static let flat = EQPreset(
        id: "flat",
        name: "Flat",
        author: "",
        category: "",
        bands: [],
        preamp: 0
    )

    /// All EQ presets bundled with the app, loaded lazily from the
    /// `EQPresets` resource directory. Includes `.flat` as the first entry.
    /// Order: Flat, then author → category → name (alphabetical).
    static let all: [EQPreset] = EQPresetLoader.shared.allPresets

    /// Presets grouped by author, for the picker UI.
    static var byAuthor: [String: [EQPreset]] { EQPresetLoader.shared.byAuthor }

    /// Legacy preset IDs from earlier app versions, mapped to their current
    /// disk-backed equivalents so existing UserDefaults selections keep
    /// working after the upgrade.
    private static let legacyIDMap: [String: String] = [
        "hd6xx": "oratory1990/over-ear/Sennheiser HD 6XX",
        "space-travel": "Kazi/in-ear/Moondrop Space Travel"
    ]

    /// Resolve an arbitrary stored ID (legacy or current) to a preset.
    /// Falls back to `.flat` when the ID is unknown or missing.
    static func resolve(id: String?) -> EQPreset {
        guard let id, !id.isEmpty else { return .flat }
        if id == "flat" { return .flat }
        let effective = legacyIDMap[id] ?? id
        return all.first { $0.id == effective } ?? .flat
    }
}

/// Parses AutoEQ `ParametricEQ.txt` files and enumerates the bundled preset
/// catalog. Files look like:
///
///     Preamp: -6.1 dB
///     Filter 1: ON LSC Fc 105 Hz Gain 6.4 dB Q 0.70
///     Filter 2: ON PK  Fc 8800 Hz Gain 5.1 dB Q 1.42
///     ...
///
/// Filter type codes used by AutoEQ over-ear/in-ear/earbud outputs:
/// `PK` (peaking), `LSC` (low shelf), `HSC` (high shelf).
final class EQPresetLoader: Sendable {
    static let shared = EQPresetLoader()

    /// All bundled presets, ordered: Flat first, then alphabetical by
    /// author → category → name.
    let allPresets: [EQPreset]

    /// Presets grouped by author, for the picker UI.
    let byAuthor: [String: [EQPreset]]

    private init() {
        var presets: [EQPreset] = [.flat]
        for entry in Self.enumerateBundled() {
            if let parsed = Self.parse(entry.url, author: entry.author, category: entry.category, name: entry.name) {
                presets.append(parsed)
            }
        }
        presets.sort { lhs, rhs in
            if lhs.author != rhs.author { return lhs.author < rhs.author }
            if lhs.category != rhs.category { return lhs.category < rhs.category }
            return lhs.name < rhs.name
        }
        self.allPresets = presets
        self.byAuthor = Dictionary(grouping: presets.filter { !$0.author.isEmpty }, by: \.author)
    }

    // MARK: - Discovery

    /// Walks the `EQPresets` resource directory. Each leaf `.txt` becomes a
    /// candidate preset whose path is `<author>/<category>/<name>.txt`.
    private static func enumerateBundled() -> [(url: URL, author: String, category: String, name: String)] {
        guard let root = Bundle.module.url(forResource: "EQPresets", withExtension: nil) else {
            return []
        }
        var out: [(URL, String, String, String)] = []
        if let authorEnumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in authorEnumerator where url.pathExtension == "txt" {
                let rel = url.deletingLastPathComponent().path(relativeTo: root)
                let parts = rel.split(separator: "/", omittingEmptySubsequences: true)
                guard parts.count == 2 else { continue }
                let author = String(parts[0])
                let category = String(parts[1])
                let name = url.deletingPathExtension().lastPathComponent
                out.append((url, author, category, name))
            }
        }
        return out
    }

    // MARK: - Parsing

    /// Parses one AutoEQ ParametricEQ.txt into an `EQPreset`. Returns nil if
    /// the file is malformed (no usable bands).
    static func parse(_ url: URL, author: String, category: String, name: String) -> EQPreset? {
        guard let body = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(body, author: author, category: category, name: name)
    }

    /// Parses AutoEQ ParametricEQ text. Exposed for tests.
    static func parse(_ body: String, author: String, category: String, name: String) -> EQPreset? {
        var preamp: Float = 0
        var bands: [EQBand] = []
        for raw in body.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Preamp:") {
                if let v = Self.firstFloat(in: line, after: "Preamp:") {
                    preamp = v
                }
                continue
            }
            if line.hasPrefix("Filter ") {
                if let band = Self.parseFilterLine(line) {
                    bands.append(band)
                }
            }
        }
        guard !bands.isEmpty else { return nil }
        return EQPreset(
            id: "\(author)/\(category)/\(name)",
            name: name,
            author: author,
            category: category,
            bands: bands,
            preamp: preamp
        )
    }

    /// Extracts the numeric value following `keyword` in `line`. Handles
    /// negative and decimal values. Returns nil if no number is found.
    private static func firstFloat(in line: String, after keyword: String) -> Float? {
        guard let range = line.range(of: keyword) else { return nil }
        let tail = line[range.upperBound...]
        let scalars = tail.unicodeScalars
        var idx = scalars.startIndex
        while idx < scalars.endIndex, CharacterSet(charactersIn: " \t:").contains(scalars[idx]) {
            idx = scalars.index(after: idx)
        }
        var num = ""
        if idx < scalars.endIndex, scalars[idx] == "-" {
            num.append("-")
            idx = scalars.index(after: idx)
        }
        while idx < scalars.endIndex {
            let c = Character(scalars[idx])
            if c.isNumber || c == "." {
                num.append(c)
                idx = scalars.index(after: idx)
            } else {
                break
            }
        }
        return Float(num)
    }

    private static func parseFilterLine(_ line: String) -> EQBand? {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 12, tokens[0] == "Filter" else { return nil }
        let state = tokens[2]
        let typeCode = tokens[3]
        guard state == "ON" else { return nil }
        guard let fc = Float(tokens[5]),
              let gain = Float(tokens[8]),
              let q = Float(tokens[11]) else { return nil }
        guard let filterType = Self.filterType(code: typeCode) else { return nil }
        return EQBand(frequency: fc, gain: gain, q: q, filterType: filterType)
    }

    private static func filterType(code: String) -> EQFilterType? {
        switch code.uppercased() {
        case "PK": return .parametric
        case "LSC", "LS": return .lowShelf
        case "HSC", "HS": return .highShelf
        default: return nil
        }
    }
}

/// Manages the AVAudioUnitEQ node and applies presets.
@MainActor
final class AudioEQ {
    let eqNode = AVAudioUnitEQ(numberOfBands: 10)

    private(set) var currentPreset: EQPreset = .flat

    /// When true, the EQ node is hard-bypassed (zero DSP) regardless of the
    /// selected preset. The preset is remembered so toggling back on restores
    /// the same sound.
    var bypassed: Bool = false {
        didSet {
            eqNode.bypass = bypassed || currentPreset.bands.isEmpty
        }
    }

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
        eqNode.bypass = bypassed || preset.bands.isEmpty
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

private extension URL {
    /// Returns the path of this URL relative to `base`, or the absolute path
    /// if it isn't actually inside `base`.
    func path(relativeTo base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let selfPath = self.standardizedFileURL.path
        if selfPath.hasPrefix(basePath + "/") {
            return String(selfPath.dropFirst(basePath.count + 1))
        }
        return selfPath
    }
}
