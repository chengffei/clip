import AppKit
import XCTest

@testable import capcap

final class WindowEffectsTests: XCTestCase {
    /// Regression for #153. Full-screen Chromium can return a direct-window
    /// alpha plane with a transparent vertical band even though the composed
    /// display pixels are visibly opaque. That alpha is not a valid silhouette
    /// for the frozen display crop and must not punch a hole into it.
    func testDisplayFillingWindowIgnoresTransparentBandInDirectWindowAlpha() throws {
        let snapshot = makeImage(width: 100, height: 100) { context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let directWindow = makeImage(width: 100, height: 100) { context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 100))
            context.fill(CGRect(x: 95, y: 0, width: 5, height: 100))
        }

        let result = WindowEffects.compositedWindowImage(
            snapshotImage: snapshot,
            directWindowImage: directWindow,
            captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            displayBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        XCTAssertEqual(try alpha(at: CGPoint(x: 90, y: 50), in: result), 255)
    }

    func testNearlyDisplayFillingWindowUsesSnapshotSilhouette() throws {
        let snapshot = makeOpaqueImage(width: 100, height: 100)
        let directWindow = makeImage(width: 100, height: 100) { context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 100))
        }

        let result = WindowEffects.compositedWindowImage(
            snapshotImage: snapshot,
            directWindowImage: directWindow,
            captureRect: CGRect(x: 0.5, y: 5, width: 99, height: 90),
            displayBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        XCTAssertEqual(try alpha(at: CGPoint(x: 90, y: 50), in: result), 255)
    }

    func testOrdinaryWindowRejectsSubstantialTransparentEdgeBand() throws {
        let snapshot = makeOpaqueImage(width: 100, height: 100)
        let directWindow = makeImage(width: 100, height: 100) { context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 100))
        }

        let result = WindowEffects.compositedWindowImage(
            snapshotImage: snapshot,
            directWindowImage: directWindow,
            captureRect: CGRect(x: 10, y: 10, width: 80, height: 80),
            displayBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        XCTAssertEqual(try alpha(at: CGPoint(x: 90, y: 50), in: result), 255)
    }

    func testOrdinaryWindowStillBorrowsReliableDirectWindowAlpha() throws {
        let snapshot = makeOpaqueImage(width: 100, height: 100)
        let directWindow = makeImage(width: 100, height: 100) { context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            context.clear(CGRect(x: 40, y: 40, width: 20, height: 20))
        }

        let result = WindowEffects.compositedWindowImage(
            snapshotImage: snapshot,
            directWindowImage: directWindow,
            captureRect: CGRect(x: 10, y: 10, width: 80, height: 80),
            displayBounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        XCTAssertEqual(try alpha(at: CGPoint(x: 50, y: 50), in: result), 0)
        XCTAssertEqual(try alpha(at: CGPoint(x: 90, y: 50), in: result), 255)
    }

    private func makeOpaqueImage(width: Int, height: Int) -> NSImage {
        makeImage(width: width, height: height) { context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func makeImage(
        width: Int,
        height: Int,
        draw: (CGContext) -> Void
    ) -> NSImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)
        return NSImage(
            cgImage: context.makeImage()!,
            size: NSSize(width: width, height: height)
        )
    }

    private func alpha(at point: CGPoint, in image: NSImage) throws -> UInt8 {
        let cgImage = try XCTUnwrap(image.cgImagePreservingBacking())
        let pixel = try XCTUnwrap(cgImage.cropping(to: CGRect(
            x: point.x,
            y: point.y,
            width: 1,
            height: 1
        )))
        var rgba = [UInt8](repeating: 0, count: 4)
        let drewPixel = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        XCTAssertTrue(drewPixel)
        return rgba[3]
    }
}
