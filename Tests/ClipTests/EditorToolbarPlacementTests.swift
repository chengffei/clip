import AppKit
import XCTest
@testable import capcap

final class EditorToolbarPlacementTests: XCTestCase {
    private let bounds = NSRect(x: 0, y: 0, width: 1_512, height: 982)
    private let toolbarSize = NSSize(width: 720, height: 44)
    private let sideToolbarSize = NSSize(width: 44, height: 300)

    func testPrimaryToolbarReservesTopSafeInsetWhenSelectionFillsScreen() {
        let rect = EditorToolbarPlacement.primaryToolbarRect(
            referenceRect: bounds,
            in: bounds,
            size: toolbarSize,
            topSafeInset: 38
        )

        XCTAssertEqual(rect.maxY, bounds.maxY - 38 - 8, accuracy: 0.001)
        XCTAssertEqual(rect.maxX, bounds.maxX - 8, accuracy: 0.001)
    }

    func testPrimaryToolbarRightAlignsWithSelection() {
        let selection = NSRect(x: 200, y: 300, width: 900, height: 500)
        let rect = EditorToolbarPlacement.primaryToolbarRect(
            referenceRect: selection,
            in: bounds,
            size: toolbarSize,
            topSafeInset: 38
        )

        XCTAssertEqual(rect.maxX, selection.maxX, accuracy: 0.001)
    }

    func testPrimaryToolbarKeepsEdgeMarginWithoutTopSafeInset() {
        let rect = EditorToolbarPlacement.primaryToolbarRect(
            referenceRect: bounds,
            in: bounds,
            size: toolbarSize,
            topSafeInset: 0
        )

        XCTAssertEqual(rect.maxY, bounds.maxY - 8, accuracy: 0.001)
    }

    func testPrimaryToolbarBelowSelectionIsUnaffectedByTopSafeInset() {
        let selection = NSRect(x: 200, y: 300, width: 900, height: 500)
        let rect = EditorToolbarPlacement.primaryToolbarRect(
            referenceRect: selection,
            in: bounds,
            size: toolbarSize,
            topSafeInset: 38
        )

        XCTAssertEqual(rect.maxY, selection.minY - 8, accuracy: 0.001)
    }

    func testSideToolbarBottomAlignsWithSelection() {
        let selection = NSRect(x: 200, y: 300, width: 900, height: 500)
        let rect = EditorToolbarPlacement.sideToolbarRect(
            referenceRect: selection,
            in: bounds,
            size: sideToolbarSize
        )

        XCTAssertEqual(rect.minX, selection.maxX + 8, accuracy: 0.001)
        XCTAssertEqual(rect.minY, selection.minY, accuracy: 0.001)
    }

    func testSideToolbarKeepsBottomScreenMargin() {
        let selection = NSRect(x: 200, y: 0, width: 900, height: 500)
        let rect = EditorToolbarPlacement.sideToolbarRect(
            referenceRect: selection,
            in: bounds,
            size: sideToolbarSize
        )

        XCTAssertEqual(rect.minY, bounds.minY + 8, accuracy: 0.001)
    }
}
