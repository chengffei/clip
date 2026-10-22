import AppKit
import XCTest
@testable import capcap

@MainActor
final class ToolbarItemTooltipTests: XCTestCase {
    func testScrollingDismissesVisibleTooltipWithoutMouseExit() throws {
        try withTile { tile, scroll in
            tile.mouseEntered(with: try hoverEvent())
            waitForTooltipDelay()
            XCTAssertTrue(tooltipIsVisible)

            scroll.contentView.scroll(to: NSPoint(x: 0, y: 80))
            XCTAssertFalse(tooltipIsVisible)
        }
    }

    func testScrollingCancelsPendingTooltipAndAllowsNextHover() throws {
        try withTile { tile, scroll in
            tile.mouseEntered(with: try hoverEvent())
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 80))
            waitForTooltipDelay()
            XCTAssertFalse(tooltipIsVisible)

            scroll.contentView.scroll(to: .zero)
            tile.mouseEntered(with: try hoverEvent())
            waitForTooltipDelay()
            XCTAssertTrue(tooltipIsVisible)
        }
    }

    private var tooltipIsVisible: Bool {
        NSApp.windows.contains { $0 is ToolTipWindow && $0.isVisible }
    }

    private func waitForTooltipDelay() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }

    private func hoverEvent() throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseEntered, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil
        ))
    }

    private func withTile(_ body: (ToolbarItemTile, NSScrollView) throws -> Void) rethrows {
        _ = NSApplication.shared
        ToolTipWindow.hide()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 500))
        let tile = ToolbarItemTile(itemID: .confirm)
        tile.frame = NSRect(x: 20, y: 20, width: 40, height: 40)
        document.addSubview(tile)
        scroll.documentView = document
        let window = NSWindow(contentRect: scroll.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = scroll
        scroll.contentView.scroll(to: .zero)
        defer {
            tile.clearTooltip()
            window.orderOut(nil)
        }
        try body(tile, scroll)
    }
}
