import AppKit
import XCTest
@testable import capcap

final class ToolbarLayoutTests: XCTestCase {
    func testDefaultPlacesSpotlightBetweenMarkerAndMosaic() throws {
        let primary = ToolbarLayout.default.primary
        let markerIndex = try XCTUnwrap(primary.firstIndex(of: .marker))
        let spotlightIndex = try XCTUnwrap(primary.firstIndex(of: .spotlight))
        let mosaicIndex = try XCTUnwrap(primary.firstIndex(of: .mosaic))

        XCTAssertEqual(spotlightIndex, markerIndex + 1)
        XCTAssertEqual(mosaicIndex, spotlightIndex + 1)
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
