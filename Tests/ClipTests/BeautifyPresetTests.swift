import XCTest
@testable import capcap

final class BeautifyPresetTests: XCTestCase {
    func testPrimaryPresetsRemainTheCompactToolbarCatalog() {
        XCTAssertEqual(BeautifyPreset.primaryPresets.count, 10)
        XCTAssertEqual(
            BeautifyPreset.primaryPresets.prefix(2).map(\.id),
            [BeautifyPreset.transparent.id, BeautifyPreset.wallpaper.id]
        )
        XCTAssertEqual(
            BeautifyPreset.defaults.prefix(BeautifyPreset.primaryPresets.count).map(\.id),
            BeautifyPreset.primaryPresets.map(\.id)
        )
    }

    func testExpandedCatalogAddsFourteenUniquePresets() {
        XCTAssertEqual(BeautifyPreset.additionalPresets.count, 14)
        XCTAssertEqual(BeautifyPreset.defaults.count, 24)

        let ids = BeautifyPreset.defaults.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryExpandedPresetCanBeResolvedByID() {
        for preset in BeautifyPreset.defaults {
            XCTAssertEqual(BeautifyPreset.preset(forID: preset.id), preset)
            XCTAssertFalse(preset.displayName.isEmpty)
        }
    }

    func testToolbarPresetsKeepTransparentAndWallpaperPinnedBeforeRecentGradients() {
        let presets = BeautifyPreset.toolbarPresets(
            preferredIDs: [
                "aurora",
                BeautifyPreset.wallpaper.id,
                "missing-preset",
                "aurora",
                "sunset-glow",
            ]
        )

        XCTAssertEqual(presets.count, 10)
        XCTAssertEqual(
            presets.prefix(4).map(\.id),
            [
                BeautifyPreset.transparent.id,
                BeautifyPreset.wallpaper.id,
                "aurora",
                "sunset-glow",
            ]
        )
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
    }

    func testPromotingMorePresetMovesItBehindPinnedPresetsAndEvictsOldestGradient() {
        let initialIDs = BeautifyPreset.toolbarPresets(preferredIDs: []).map(\.id)
        let promotedIDs = BeautifyPreset.promotedToolbarPresetIDs(
            selecting: "aurora",
            currentIDs: []
        )
        let promotedPresets = BeautifyPreset.toolbarPresets(preferredIDs: promotedIDs)

        XCTAssertEqual(
            promotedPresets.prefix(3).map(\.id),
            [
                BeautifyPreset.transparent.id,
                BeautifyPreset.wallpaper.id,
                "aurora",
            ]
        )
        XCTAssertEqual(promotedPresets.count, initialIDs.count)
        XCTAssertFalse(promotedPresets.map(\.id).contains(initialIDs.last!))
    }

    func testPickerExcludesEveryPresetAlreadyVisibleInToolbar() {
        let toolbarPresets = BeautifyPreset.toolbarPresets(
            preferredIDs: ["aurora", "sunset-glow"]
        )
        let pickerPresets = BeautifyPreset.pickerPresets(
            excluding: toolbarPresets
        )
        let toolbarIDs = Set(toolbarPresets.map(\.id))
        let pickerIDs = Set(pickerPresets.map(\.id))

        XCTAssertEqual(toolbarPresets.count, 10)
        XCTAssertEqual(pickerPresets.count, 14)
        XCTAssertTrue(toolbarIDs.isDisjoint(with: pickerIDs))
        XCTAssertEqual(toolbarIDs.union(pickerIDs).count, BeautifyPreset.defaults.count)
    }
}
