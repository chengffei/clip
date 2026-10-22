import AppKit
import XCTest
@testable import capcap

@MainActor
final class MosaicAnnotationTranslationTests: XCTestCase {
    func testDraggingMosaicRepixelatesAtDestination() throws {
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        canvas.overrideBaseImage = try makeHalfRedHalfBlueImage()
        canvas.currentMosaicBlockSize = 8
        canvas.activeTool = .mosaic

        // Draw a mosaic over the red half.
        canvas.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: NSPoint(x: 10, y: 40)))
        canvas.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, point: NSPoint(x: 40, y: 70)))
        canvas.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: NSPoint(x: 40, y: 70)))

        XCTAssertTrue(canvas.selectAllAnnotations())
        let original = try XCTUnwrap(canvas.selectedAnnotation as? MosaicAnnotation)
        let originalRed = try XCTUnwrap(centerColor(of: original.pixelatedImage))
        XCTAssertGreaterThan(originalRed.redComponent, 0.6)
        XCTAssertLessThan(originalRed.blueComponent, 0.4)

        // Drag the frame to the blue half. The frame itself should decide
        // what gets pixelated, so the moved mosaic must sample blue pixels
        // instead of carrying the red texture along.
        let start = NSPoint(x: original.rect.midX, y: original.rect.midY)
        let delta = NSPoint(x: 50, y: 0)
        canvas.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: start))
        canvas.mouseDragged(with: try mouseEvent(
            type: .leftMouseDragged,
            point: NSPoint(x: start.x + delta.x, y: start.y + delta.y)
        ))
        canvas.mouseUp(with: try mouseEvent(
            type: .leftMouseUp,
            point: NSPoint(x: start.x + delta.x, y: start.y + delta.y)
        ))

        let moved = try XCTUnwrap(canvas.selectedAnnotation as? MosaicAnnotation)
        XCTAssertEqual(moved.rect.minX, original.rect.minX + delta.x, accuracy: 0.001)
        let movedColor = try XCTUnwrap(centerColor(of: moved.pixelatedImage))
        XCTAssertGreaterThan(movedColor.blueComponent, 0.6)
        XCTAssertLessThan(movedColor.redComponent, 0.4)
    }

    private func centerColor(of image: NSImage) -> NSColor? {
        guard
            let rep = image.bitmapImageRepPreservingBacking(),
            rep.pixelsWide > 0,
            rep.pixelsHigh > 0
        else {
            return nil
        }
        return rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?
            .usingColorSpace(.deviceRGB)
    }

    private func makeHalfRedHalfBlueImage() throws -> NSImage {
        let width = 100
        let height = 100
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = NSSize(width: width, height: height)

        let graphicsContext = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: width / 2, height: height).fill()
        NSColor.blue.setFill()
        NSRect(x: width / 2, y: 0, width: width / 2, height: height).fill()
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private func mouseEvent(type: NSEvent.EventType, point: NSPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}
