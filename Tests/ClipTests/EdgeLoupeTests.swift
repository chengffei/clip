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

final class SelectionKeyboardAdjustmentTests: XCTestCase {
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    func testArrowKeyMapping() {
        XCTAssertEqual(SelectionView.keyboardAdjustment(for: key(123)), .move(CGVector(dx: -1, dy: 0)))
        XCTAssertEqual(SelectionView.keyboardAdjustment(for: key(126, .shift)), .move(CGVector(dx: 0, dy: 10)))
        XCTAssertEqual(SelectionView.keyboardAdjustment(for: key(124, .command)), .resize(CGVector(dx: 1, dy: 0)))
        XCTAssertEqual(SelectionView.keyboardAdjustment(for: key(125, [.command, .shift])), .resize(CGVector(dx: 0, dy: -10)))
        XCTAssertNil(SelectionView.keyboardAdjustment(for: key(123, .option)))
        XCTAssertNil(SelectionView.keyboardAdjustment(for: key(0)))
    }

    func testMoveAndResizeKeepTopLeftForResize() {
        _ = NSApplication.shared
        let view = SelectionView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.updateSelectionRect(NSRect(x: 100, y: 100, width: 100, height: 50))
        XCTAssertTrue(view.adjustFromKeyboard(.move(CGVector(dx: -1, dy: 0))))
        XCTAssertEqual(view.currentSelectionRect, NSRect(x: 99, y: 100, width: 100, height: 50))
        // ⌘↓: bottom edge down, top edge (maxY 150) fixed.
        view.adjustFromKeyboard(.resize(CGVector(dx: 0, dy: -10)))
        XCTAssertEqual(view.currentSelectionRect, NSRect(x: 99, y: 90, width: 100, height: 60))
        // ⌘←: right edge in.
        view.adjustFromKeyboard(.resize(CGVector(dx: -1, dy: 0)))
        XCTAssertEqual(view.currentSelectionRect, NSRect(x: 99, y: 90, width: 99, height: 60))
        // Moving stops at the view's edge.
        view.adjustFromKeyboard(.move(CGVector(dx: -500, dy: 0)))
        XCTAssertEqual(view.currentSelectionRect?.minX, 0)
    }
}
