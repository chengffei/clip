import AppKit
import XCTest
@testable import Clip

/// Edge loupe geometry, plus an offscreen render of the lens and the dashed
/// frame when `CLIP_SNAPSHOT_DIR` is set (edge-loupe.png).
final class EdgeLoupeTests: XCTestCase {
    func testAnchorSitsOnTheDraggedEdge() {
        let rect = NSRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(SelectionView.loupeAnchor(handle: .topLeft, rect: rect, cursor: NSPoint(x: 97, y: 203)), NSPoint(x: 100, y: 200))
        XCTAssertEqual(SelectionView.loupeAnchor(handle: .rightCenter, rect: rect, cursor: NSPoint(x: 305, y: 140)), NSPoint(x: 300, y: 140))
        XCTAssertEqual(SelectionView.loupeAnchor(handle: .bottomCenter, rect: rect, cursor: NSPoint(x: 999, y: 98)), NSPoint(x: 300, y: 100))
    }

    func testLensGoesInwardAndFlipsAtScreenEdges() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let size = EdgeLoupeWindow.lensSize, gap = EdgeLoupeWindow.cursorGap
        // Bottom-right handle: lens up-left of the cursor (inside the selection).
        let inward = EdgeLoupeWindow.origin(cursor: NSPoint(x: 500, y: 400), placement: CGVector(dx: -1, dy: 1), screenFrame: screen)
        XCTAssertEqual(inward, NSPoint(x: 500 - gap - size, y: 400 + gap))
        // Near the left screen edge the lens flips to the right of the cursor.
        let flipped = EdgeLoupeWindow.origin(cursor: NSPoint(x: 40, y: 400), placement: CGVector(dx: -1, dy: 0), screenFrame: screen)
        XCTAssertEqual(flipped.x, 40 + gap)
        XCTAssertEqual(flipped.y, 400 - size / 2)
    }

    func testRenderLoupe() throws {
        guard let dir = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_DIR"] else { return }
        _ = NSApplication.shared
        // 2x "desktop": text-like bars on white so pixels and the edge are visible.
        let pointSize = NSSize(width: 400, height: 300)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = pointSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(origin: .zero, size: pointSize).fill()
        for i in 0..<20 {
            (i % 2 == 0 ? NSColor.systemOrange : NSColor.darkGray).setFill()
            NSRect(x: 40 + CGFloat(i % 5) * 9, y: 40 + CGFloat(i) * 11, width: 220, height: 4.5).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = try XCTUnwrap(rep.cgImage)

        let selection = NSRect(x: 120, y: 80, width: 160, height: 140)
        let view = EdgeLoupeView(frame: NSRect(x: 0, y: 0, width: EdgeLoupeWindow.lensSize, height: EdgeLoupeWindow.lensSize))
        view.configure(image: image, imageBounds: NSRect(origin: .zero, size: pointSize), anchor: NSPoint(x: 120, y: 150), selection: selection)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        let out = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: out)
        try XCTUnwrap(out.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("edge-loupe.png"))
    }
}
