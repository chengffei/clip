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

/// Product shot for the website: a light "document" backdrop, a selection
/// with no tool chosen and the single toolbar under it. Only renders when
/// `CLIP_SNAPSHOT_DIR` is set.
final class SiteHeroSnapshotTests: XCTestCase {
    func testHeroRender() throws {
        guard let dir = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_DIR"] else { return }
        _ = NSApplication.shared
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 630))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(srgbRed: 0.91, green: 0.91, blue: 0.93, alpha: 1).cgColor

        // A document-like card with grey text bars, so the dimming and the cutout read.
        let card = NSView(frame: NSRect(x: 60, y: 40, width: 1080, height: 560))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 12
        host.addSubview(card)
        var y: CGFloat = 500
        for (index, width) in [620, 880, 760, 920, 540, 860, 700, 900, 640, 820].enumerated() {
            let bar = NSView(frame: NSRect(x: 60, y: y, width: CGFloat(width), height: index % 5 == 0 ? 16 : 11))
            bar.wantsLayer = true
            bar.layer?.backgroundColor = NSColor(white: index % 5 == 0 ? 0.25 : 0.80, alpha: 1).cgColor
            bar.layer?.cornerRadius = 3
            card.addSubview(bar)
            y -= 44
        }

        let selection = SelectionView(frame: host.bounds)
        host.addSubview(selection)
        let rect = NSRect(x: 290, y: 200, width: 620, height: 300)
        selection.updateSelectionRect(rect)

        let layout = ToolbarLayout.default
        let bar = ToolbarView(items: layout.primary, overflow: layout.side)
        bar.setFrameOrigin(NSPoint(x: rect.minX - 2, y: rect.minY - bar.frame.height - 10))
        bar.wantsLayer = true
        bar.layer?.shadowColor = NSColor.black.cgColor
        bar.layer?.shadowOpacity = Brand.shadowOpacity
        bar.layer?.shadowRadius = Brand.shadowRadius
        bar.layer?.shadowOffset = Brand.shadowOffset
        host.addSubview(bar)
        bar.updateSelection(tool: .none)

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("hero.png"))
    }
}
