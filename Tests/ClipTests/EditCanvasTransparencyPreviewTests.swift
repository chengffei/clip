import AppKit
import XCTest
@testable import capcap

@MainActor
final class EditCanvasTransparencyPreviewTests: XCTestCase {
    func testTransparentBaseImageUsesStablePreviewBackdrop() throws {
        let image = try Self.makeTransparentImage()
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        canvas.overrideBaseImage = image

        let rendered = try Self.render(canvas: canvas, background: .systemRed)
        let corner = try XCTUnwrap(rendered.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))

        XCTAssertEqual(corner.redComponent, corner.greenComponent, accuracy: 0.01)
        XCTAssertEqual(corner.greenComponent, corner.blueComponent, accuracy: 0.01)
        XCTAssertGreaterThan(corner.redComponent, 0.65)
        XCTAssertLessThan(corner.redComponent, 0.95)
    }

    func testBeautifyContainerOwnsTransparencyPreviewBackground() {
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        let container = BeautifyContainerView(canvasView: canvas)

        container.setBeautify(preset: .defaultPreset)
        XCTAssertFalse(canvas.drawsTransparencyBackdrop)

        container.setBeautify(preset: nil)
        XCTAssertTrue(canvas.drawsTransparencyBackdrop)
    }

    func testPreviewBackdropIsNotBakedIntoExport() throws {
        let image = try Self.makeTransparentImage()
        let canvas = EditCanvasView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        canvas.overrideBaseImage = image

        let exported = try XCTUnwrap(canvas.compositeImage(fallbackBaseImage: image))
        let cgImage = try XCTUnwrap(exported.cgImagePreservingBacking())

        XCTAssertEqual(try Self.alpha(in: cgImage, x: 0, y: 0), 0)
    }

    private static func makeTransparentImage() throws -> NSImage {
        let width = 4
        let height = 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let centerOffset = (1 * width + 1) * 4
        pixels[centerOffset] = 40
        pixels[centerOffset + 1] = 100
        pixels[centerOffset + 2] = 220
        pixels[centerOffset + 3] = 255

        let cgImage = pixels.withUnsafeMutableBytes { bytes in
            CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
        return NSImage(
            cgImage: try XCTUnwrap(cgImage),
            size: NSSize(width: width, height: height)
        )
    }

    private static func render(canvas: EditCanvasView, background: NSColor) throws -> NSBitmapImageRep {
        let width = Int(canvas.bounds.width)
        let height = Int(canvas.bounds.height)
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
        rep.size = canvas.bounds.size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        background.setFill()
        canvas.bounds.fill()
        canvas.draw(canvas.bounds)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func alpha(in image: CGImage, x: Int, y: Int) throws -> UInt8 {
        let pixelImage = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        let drewPixel = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(pixelImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        XCTAssertTrue(drewPixel)
        return pixel[3]
    }
}
