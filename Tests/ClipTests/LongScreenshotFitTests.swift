import AppKit
import XCTest
@testable import Clip

/// A finished long screenshot is shown whole, scaled to fit the screen,
/// instead of a selection-sized window the user has to scroll (2026-10-28).
final class LongScreenshotFitTests: XCTestCase {
    @MainActor
    func testLongScreenshotFitsWithoutScrolling() throws {
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

        let image = NSImage(size: NSSize(width: 600, height: 4000), flipped: false) { rect in
            NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1).setFill()
            rect.fill()
            for line in 0..<200 {
                NSString(string: "line \(line + 1)").draw(at: NSPoint(x: 12, y: rect.height - CGFloat(line + 1) * 20),
                    withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)])
            }
            return true
        }
        controller.loadLongScreenshotForTesting(image)

        let scrollView = try XCTUnwrap(controller.canvasScrollViewForTesting)
        let document = try XCTUnwrap(scrollView.documentView)
        XCTAssertLessThanOrEqual(document.frame.height, scrollView.contentView.bounds.height + 0.5, "needs scrolling")
        XCTAssertGreaterThan(scrollView.frame.height, selectionRect.height, "frame did not grow")
        XCTAssertTrue(screen.visibleFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY).contains(scrollView.frame))

        if let dir = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_DIR"] {
            let rep = try XCTUnwrap(selectionView.bitmapImageRepForCachingDisplay(in: selectionView.bounds))
            selectionView.cacheDisplay(in: selectionView.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(dir)/long-fit.png"))
        }
    }
}
