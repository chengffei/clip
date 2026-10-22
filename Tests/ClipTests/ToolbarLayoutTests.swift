import AppKit
import XCTest
@testable import Clip

final class ToolbarLayoutTests: XCTestCase {
    /// Clip's default keeps the main bar to twelve tools; spotlight is hidden
    /// until the user drags it in from Settings › Toolbar.
    func testDefaultKeepsMainBarToTwelveToolsAndHidesSpotlight() {
        let layout = ToolbarLayout.default
        XCTAssertEqual(layout.primary.count, 12)
        XCTAssertTrue(layout.hidden.contains(.spotlight))
        XCTAssertFalse(layout.primary.contains(.spotlight))
        XCTAssertEqual(layout.side.last, .confirm)
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
