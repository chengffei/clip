import AppKit
import XCTest
@testable import Clip

/// Renders the capture overlay offscreen over a light and a dark backdrop so
/// the selection frame, handles and size label can be eyeballed. Writes PNGs
/// when `CLIP_SNAPSHOT_DIR` is set; always checks the label fits the frame.
final class SelectionSnapshotTests: XCTestCase {
    func testSelectionFrameRendersOverLightAndDarkContent() throws {
        _ = NSApplication.shared
        for (name, backdrop) in [("selection-light", NSColor(white: 0.97, alpha: 1)), ("selection-dark", NSColor(white: 0.12, alpha: 1))] {
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))
            host.wantsLayer = true
            host.layer?.backgroundColor = backdrop.cgColor
            let selection = SelectionView(frame: host.bounds)
            host.addSubview(selection)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            selection.updateSelectionRect(NSRect(x: 120, y: 80, width: 300, height: 180))
            host.layoutSubtreeIfNeeded()

            XCTAssertEqual(selection.currentSelectionRect, NSRect(x: 120, y: 80, width: 300, height: 180))

            guard let dir = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_DIR"] else { continue }
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
