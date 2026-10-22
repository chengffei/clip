import AppKit
import XCTest
@testable import Clip

/// Renders the editor toolbar offscreen from the default layout. Writes a PNG
/// when `CLIP_SNAPSHOT_DIR` is set; always checks the zone structure.
final class ToolbarSnapshotTests: XCTestCase {
    func testDefaultToolbarRendersAsOneBar() throws {
        _ = NSApplication.shared
        let layout = ToolbarLayout.default
        let bar = ToolbarView(items: layout.primary, overflow: layout.side)
        let host = NSView(frame: NSRect(origin: .zero, size: NSSize(width: bar.frame.width + 40, height: bar.frame.height + 40)))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
        bar.setFrameOrigin(NSPoint(x: 20, y: 20))
        host.addSubview(bar)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        bar.updateSelection(tool: .rectangle)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(bar.frame.height, ToolbarView.buttonSize + ToolbarView.crossPadding * 2)
        XCTAssertTrue(bar.contains(.rectangle))
        XCTAssertTrue(bar.contains(.marker), "overflow items count as reachable")
        XCTAssertNotNil(bar.frame(for: .confirm))
        let close = try XCTUnwrap(bar.frame(for: .close))
        let confirm = try XCTUnwrap(bar.frame(for: .confirm))
        XCTAssertLessThan(close.maxX, confirm.minX, "close sits left, confirm sits right")

        guard let dir = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_DIR"] else { return }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("toolbar.png"))
    }
}
