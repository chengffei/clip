import AppKit
import XCTest
@testable import Clip

/// The long screenshot result viewport can be resized, moved and fill the
/// screen, so the user can switch between the whole image and its detail
/// (2026-11-02).
final class LongScreenshotViewportTests: XCTestCase {
    @MainActor
    func testViewportResizesFillsScreenAndZooms() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let selectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window.contentView = selectionView
        let selectionRect = NSRect(x: 300, y: screen.frame.height - 520, width: 600, height: 400)
        selectionView.updateSelectionRect(selectionRect)
        let controller = EditWindowController(
            captureRect: selectionRect, screen: screen, selectionRect: selectionRect,
            selectionViewRect: selectionRect, hostSelectionView: selectionView,
            windowBaseImage: NSImage(size: selectionRect.size), isWindowCapture: false, onComplete: { _ in }
        )
        controller.show()
        defer { controller.tearDown() }

        let image = NSImage(size: NSSize(width: 1000, height: 6000), flipped: false) { rect in
            NSColor.darkGray.setFill()
            rect.fill()
            return true
        }
        controller.loadLongScreenshotForTesting(image)
        let scrollView = try XCTUnwrap(controller.canvasScrollViewForTesting)
        let document = try XCTUnwrap(scrollView.documentView)
        let fitted = scrollView.frame

        // Handles are live and drive the viewport, not the capture selection.
        let chrome = try XCTUnwrap(controller.selectionChromeOverlayForTesting)
        XCTAssertTrue(chrome.isActiveAndVisible)
        let handler = try XCTUnwrap(chrome.viewportResizeHandler)
        let wider = NSRect(x: fitted.minX - 200, y: fitted.minY, width: fitted.width + 400, height: fitted.height)
        handler(wider, true)
        XCTAssertEqual(scrollView.frame, wider.integral)
        XCTAssertEqual(chrome.selectionRectInView, wider.integral)
        // The image did not stretch and stays centred in the wider viewport.
        XCTAssertEqual(scrollView.magnification, 1, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentView.bounds.midX, document.frame.midX, accuracy: 1)

        // Too small is clamped to the minimum.
        handler(NSRect(x: wider.minX, y: wider.minY, width: 20, height: 20), true)
        XCTAssertGreaterThanOrEqual(scrollView.frame.width, 240)
        XCTAssertGreaterThanOrEqual(scrollView.frame.height, 160)

        // Fill the screen: viewport grows to the visible area and fits width.
        let beforeFill = scrollView.frame
        XCTAssertTrue(controller.performLongScreenshotViewCommand(.toggleFillScreen))
        XCTAssertTrue(controller.isLongScreenshotFillingScreen)
        let visible = screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        XCTAssertEqual(scrollView.frame, visible.insetBy(dx: 40, dy: 60).integral)
        XCTAssertEqual(scrollView.contentView.bounds.width, document.frame.width, accuracy: 1)
        XCTAssertGreaterThan(document.frame.height, scrollView.contentView.bounds.height, "detail view should scroll")

        // Real size and zoom stay inside the limits.
        controller.performLongScreenshotViewCommand(.actualSize)
        XCTAssertEqual(scrollView.magnification * document.frame.width, 1000, accuracy: 1, "real size shows image points 1:1")
        controller.performLongScreenshotViewCommand(.zoomIn)
        XCTAssertLessThanOrEqual(scrollView.magnification, scrollView.maxMagnification + 0.001)

        // Whole image fits again.
        controller.performLongScreenshotViewCommand(.fitWhole)
        XCTAssertLessThanOrEqual(document.frame.height, scrollView.contentView.bounds.height + 1)

        // Toggling back restores the earlier viewport.
        controller.performLongScreenshotViewCommand(.toggleFillScreen)
        XCTAssertFalse(controller.isLongScreenshotFillingScreen)
        XCTAssertEqual(scrollView.frame, beforeFill)

        if let dir = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_DIR"] {
            controller.performLongScreenshotViewCommand(.toggleFillScreen)
            let rep = try XCTUnwrap(selectionView.bitmapImageRepForCachingDisplay(in: selectionView.bounds))
            selectionView.cacheDisplay(in: selectionView.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(dir)/long-fill.png"))
        }
    }
}
