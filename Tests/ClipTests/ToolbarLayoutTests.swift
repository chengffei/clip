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
