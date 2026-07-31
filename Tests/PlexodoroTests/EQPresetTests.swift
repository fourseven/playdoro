import XCTest
import Foundation
@testable import PlexodoroKit

final class EQPresetTests: XCTestCase {

    // MARK: - Parser

    func testParsesCanonicalAutoEQFile() {
        let body = """
        Preamp: -6.1 dB
        Filter 1: ON LSC Fc 105 Hz Gain 6.4 dB Q 0.70
        Filter 2: ON PK Fc 8800 Hz Gain 5.1 dB Q 1.42
        Filter 3: ON PK Fc 118 Hz Gain -3.1 dB Q 0.50
        Filter 4: ON HSC Fc 10000 Hz Gain -2.1 dB Q 0.70
        """
        let preset = EQPresetLoader.parse(
            body,
            author: "oratory1990",
            category: "over-ear",
            name: "Sennheiser HD 6XX"
        )
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.preamp, -6.1)
        XCTAssertEqual(preset?.id, "oratory1990/over-ear/Sennheiser HD 6XX")
        XCTAssertEqual(preset?.author, "oratory1990")
        XCTAssertEqual(preset?.category, "over-ear")
        XCTAssertEqual(preset?.bands.count, 4)

        XCTAssertEqual(preset?.bands[0].frequency, 105)
        XCTAssertEqual(preset?.bands[0].gain, 6.4)
        XCTAssertEqual(preset?.bands[0].q, 0.70)
        XCTAssertEqual(preset?.bands[0].filterType, .lowShelf)

        XCTAssertEqual(preset?.bands[1].filterType, .parametric)

        XCTAssertEqual(preset?.bands[2].gain, -3.1)
        XCTAssertEqual(preset?.bands[2].filterType, .parametric)

        XCTAssertEqual(preset?.bands[3].frequency, 10000)
        XCTAssertEqual(preset?.bands[3].filterType, .highShelf)
    }

    func testParserIgnoresOffFilters() {
        let body = """
        Preamp: -1.0 dB
        Filter 1: OFF PK Fc 100 Hz Gain 1.0 dB Q 0.70
        Filter 2: ON PK Fc 200 Hz Gain 2.0 dB Q 1.00
        """
        let preset = EQPresetLoader.parse(body, author: "a", category: "c", name: "n")
        XCTAssertEqual(preset?.bands.count, 1)
        XCTAssertEqual(preset?.bands.first?.frequency, 200)
    }

    func testParserReturnsNilForNoActiveBands() {
        let body = """
        Preamp: 0.0 dB
        Filter 1: OFF PK Fc 100 Hz Gain 1.0 dB Q 0.70
        """
        let preset = EQPresetLoader.parse(body, author: "a", category: "c", name: "n")
        XCTAssertNil(preset)
    }

    func testParserHandlesNegativePreampOnly() {
        let body = """
        Preamp: -5.6 dB
        Filter 1: ON LSC Fc 105 Hz Gain -4.2 dB Q 0.70
        """
        let preset = EQPresetLoader.parse(body, author: "a", category: "c", name: "n")
        XCTAssertEqual(preset?.preamp, -5.6)
        XCTAssertEqual(preset?.bands.first?.gain, -4.2)
    }

    // MARK: - ID resolution / legacy migration

    func testResolveNilReturnsFlat() {
        XCTAssertEqual(EQPreset.resolve(id: nil), .flat)
    }

    func testResolveEmptyReturnsFlat() {
        XCTAssertEqual(EQPreset.resolve(id: ""), .flat)
    }

    func testResolveFlatReturnsFlat() {
        XCTAssertEqual(EQPreset.resolve(id: "flat"), .flat)
    }

    func testResolveUnknownIDReturnsFlat() {
        XCTAssertEqual(EQPreset.resolve(id: "nonsense/never/here"), .flat)
    }

    func testResolveLegacyHD6XXIDMapsToBundledPreset() {
        let resolved = EQPreset.resolve(id: "hd6xx")
        XCTAssertEqual(resolved.id, "oratory1990/over-ear/Sennheiser HD 6XX")
        XCTAssertEqual(resolved.name, "Sennheiser HD 6XX")
        XCTAssertFalse(resolved.bands.isEmpty)
        XCTAssertEqual(resolved.preamp, -6.1, accuracy: 0.001)
    }

    func testResolveLegacySpaceTravelIDMapsToBundledPreset() {
        let resolved = EQPreset.resolve(id: "space-travel")
        XCTAssertEqual(resolved.id, "Kazi/in-ear/Moondrop Space Travel")
        XCTAssertEqual(resolved.name, "Moondrop Space Travel")
        XCTAssertEqual(resolved.preamp, -5.6, accuracy: 0.001)
    }

    // MARK: - Catalog

    func testCatalogIncludesBothAuthors() {
        let authors = Set(EQPreset.byAuthor.keys)
        XCTAssertTrue(authors.contains("oratory1990"))
        XCTAssertTrue(authors.contains("Kazi"))
    }

    func testCatalogFlatIsAlwaysFirst() {
        XCTAssertEqual(EQPreset.all.first, .flat)
    }

    func testCatalogHasHundredsOfPresets() {
        // Sanity: oratory1990 + Kazi together produce 800+ presets.
        XCTAssertGreaterThan(EQPreset.all.count, 800)
    }

    func testEveryPresetHasAtLeastOneBand() {
        for preset in EQPreset.all where preset.id != "flat" {
            XCTAssertFalse(preset.bands.isEmpty, "Preset \(preset.id) has no bands")
        }
    }

    func testEveryPresetIDIsUnique() {
        let ids = EQPreset.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate preset IDs in catalog")
    }

    func testCatalogIsSortedByAuthorCategoryName() {
        let nonFlat = EQPreset.all.filter { $0.id != "flat" }
        let sorted = nonFlat.sorted { lhs, rhs in
            if lhs.author != rhs.author { return lhs.author < rhs.author }
            if lhs.category != rhs.category { return lhs.category < rhs.category }
            return lhs.name < rhs.name
        }
        XCTAssertEqual(nonFlat.map(\.id), sorted.map(\.id))
    }

    func testSennheiserHD6XXMatchesPreviousHardcodedBands() {
        // The previously-hardcoded .hd6xx preset should match the disk-backed
        // version, byte-for-band, so existing users hear no change.
        let resolved = EQPreset.resolve(id: "hd6xx")
        // First band was LSC 105 Hz / +6.4 dB / Q 0.70
        let first = resolved.bands.first { $0.filterType == .lowShelf && abs($0.frequency - 105) < 0.01 }
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.gain ?? 0, 6.4, accuracy: 0.001)
        XCTAssertEqual(first?.q ?? 0, 0.70, accuracy: 0.001)
    }

    // MARK: - Recent presets

    func testRecentMergePrependsNewID() {
        let result = mergeRecentEQPresets(existing: ["a", "b"], added: "c", maxRetained: 3)
        XCTAssertEqual(result, ["c", "a", "b"])
    }

    func testRecentMergeMovesExistingToFront() {
        let result = mergeRecentEQPresets(existing: ["a", "b", "c"], added: "b", maxRetained: 3)
        XCTAssertEqual(result, ["b", "a", "c"])
    }

    func testRecentMergeCapsAtMax() {
        let result = mergeRecentEQPresets(existing: ["a", "b", "c"], added: "d", maxRetained: 3)
        XCTAssertEqual(result, ["d", "a", "b"])
    }

    func testRecentMergeDedupes() {
        let result = mergeRecentEQPresets(existing: ["a", "a", "b"], added: "a", maxRetained: 3)
        XCTAssertEqual(result, ["a", "b"])
    }
}
