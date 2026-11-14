import AppKit
import XCTest
@testable import Clip

/// Annotated and rotated exports must keep the snapshot's colors. Screen
/// snapshots carry the display's color space (Display P3 on recent Macs);
/// compositing into device RGB clipped P3 red (255,0,0) to (234,51,35).
@MainActor
final class ExportColorFidelityTests: XCTestCase {
    private static let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

    private func p3Image(width: Int = 40, height: Int = 40) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: Self.p3,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        context.setFillColor(CGColor(colorSpace: Self.p3, components: [1.0, 0.0, 0.0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    /// The color of pixel (x, y) as Display P3 bytes, after color matching.
    private func p3Pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: Self.p3, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        }
        return pixel
    }

    func testAnnotatedExportKeepsSnapshotColors() throws {
        let source = try p3Image()
        let base = NSImage(cgImage: source, size: NSSize(width: 20, height: 20))
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        canvas.overrideBaseImage = base
        canvas.activeTool = .rectangle
        for (type, point) in [(NSEvent.EventType.leftMouseDown, NSPoint(x: 1, y: 1)),
                              (.leftMouseDragged, NSPoint(x: 6, y: 6)),
                              (.leftMouseUp, NSPoint(x: 6, y: 6))] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }

        let exported = try XCTUnwrap(canvas.compositeImage(fallbackBaseImage: base)?.cgImagePreservingBacking())
        XCTAssertEqual(exported.width, source.width)
        // Far from the rectangle, the pixel must look exactly like the source.
        let expected = try p3Pixel(source, x: 32, y: 8)
        let actual = try p3Pixel(exported, x: 32, y: 8)
        for channel in 0..<3 {
            XCTAssertEqual(Int(actual[channel]), Int(expected[channel]), accuracy: 1,
                           "channel \(channel): \(actual) vs \(expected)")
        }
    }

    func testRotatedExportKeepsSnapshotColors() throws {
        let source = try p3Image()
        let base = NSImage(cgImage: source, size: NSSize(width: 20, height: 20))
        let rotated = try XCTUnwrap(ImageRotation.left.render(base)?.cgImagePreservingBacking())
        let expected = try p3Pixel(source, x: 10, y: 10)
        let actual = try p3Pixel(rotated, x: 10, y: 10)
        for channel in 0..<3 {
            XCTAssertEqual(Int(actual[channel]), Int(expected[channel]), accuracy: 1,
                           "channel \(channel): \(actual) vs \(expected)")
        }
    }
}
