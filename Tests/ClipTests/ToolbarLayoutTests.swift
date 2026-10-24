import AppKit
import XCTest
@testable import Clip

final class ToolbarLayoutTests: XCTestCase {
    /// One bar: close first, confirm last, shapes together, spotlight hidden.
    func testDefaultIsOneBarWithCloseFirstAndConfirmLast() {
        let layout = ToolbarLayout.default
        XCTAssertEqual(layout.primary.first, .close)
        XCTAssertEqual(layout.primary.last, .confirm)
        XCTAssertTrue(layout.hidden.contains(.spotlight))
        XCTAssertFalse(layout.side.contains(.moveSelection), "drag handle cannot live in a menu")
        XCTAssertTrue(ToolbarView.shapeFamily.allSatisfy { layout.primary.contains($0) })
    }

    func testOlderPersistedLayoutAddsSpotlightAfterMarker() throws {
        let oldLayout = ToolbarLayout(
            primary: [.rectangle, .marker, .mosaic],
            side: [.save, .confirm],
            hidden: ToolbarLayout.canonicalOrder.filter {
                ![.rectangle, .marker, .spotlight, .mosaic, .save, .confirm].contains($0)
            }
        )

        let normalized = oldLayout.normalized()
        let markerIndex = try XCTUnwrap(normalized.primary.firstIndex(of: .marker))
        let spotlightIndex = try XCTUnwrap(normalized.primary.firstIndex(of: .spotlight))
        let mosaicIndex = try XCTUnwrap(normalized.primary.firstIndex(of: .mosaic))

        XCTAssertEqual(spotlightIndex, markerIndex + 1)
        XCTAssertEqual(mosaicIndex, spotlightIndex + 1)
    }

    func testSpotlightToolbarSymbolExistsOnSupportedmacOS() {
        XCTAssertNotNil(
            NSImage(
                systemSymbolName: ToolbarItemID.spotlight.symbolName,
                accessibilityDescription: nil
            )
        )
    }
}

final class ToolbarDividerTests: XCTestCase {
    func testDefaultLayoutCarriesThreeDividersAndParksTheSpare() {
        let layout = ToolbarLayout.default
        XCTAssertEqual(layout.primary.filter(\.isDivider).count, 3)
        XCTAssertTrue(layout.hidden.contains(.divider4))
    }

    func testLegacyLayoutGainsDividersAlongTheOldZones() {
        let legacy = ToolbarLayout(dictionary: [
            "primary": ["close", "rectangle", "pen", "undo", "redo", "ocr", "save", "confirm"],
            "side": ["marker"],
            "hidden": [],
        ]).normalized()
        // normalized() also slots in tools the legacy dictionary lacked, so
        // compare the relative order of the ones we named.
        let named: Set<String> = ["close", "divider1", "rectangle", "pen", "divider2", "undo", "redo", "divider3", "ocr", "save", "confirm"]
        XCTAssertEqual(
            legacy.primary.map(\.rawValue).filter { named.contains($0) },
            ["close", "divider1", "rectangle", "pen", "divider2", "undo", "redo", "divider3", "ocr", "save", "confirm"]
        )
        XCTAssertTrue(legacy.hidden.contains(.divider4))
        XCTAssertEqual((legacy.primary + legacy.side + legacy.hidden).filter(\.isDivider).count, 4)
    }

    func testDividersBecomeGapsAndMoreGoesLast() {
        let slots = ToolbarView.buildSlots(
            items: [.divider1, .close, .divider2, .divider3, .pen, .text, .divider4],
            hasOverflow: true
        )
        var picture: [String] = []
        for slot in slots {
            switch slot {
            case .item(let id): picture.append(id.rawValue)
            case .gap: picture.append("|")
            case .more: picture.append("more")
            case .shapeGroup: picture.append("shapes")
            }
        }
        XCTAssertEqual(picture, ["close", "|", "pen", "text", "|", "more"])
    }

    func testDividersNeverTakeShortcuts() {
        XCTAssertFalse(ToolbarItemID.divider1.supportsEditorShortcut)
        XCTAssertNotNil(ToolbarItemID.divider2.iconImage(pointSize: 15))
    }
}
