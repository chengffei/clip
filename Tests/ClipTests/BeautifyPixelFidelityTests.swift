import AppKit
import XCTest

@testable import Clip

final class BeautifyPixelFidelityTests: XCTestCase {
    func testPNGExportPreservesInteriorPixelsWithFractionalPadding() throws {
        for scale: CGFloat in [1, 1.5, 2] {
            for padding: CGFloat in [0, 9, 9.3, 9.75] {
                for shadow in [false, true] {
                    let source = try makeSource(scale: scale)
                    let output = BeautifyRenderer.render(
                        innerImage: source, preset: .transparent,
                        padding: padding, shadowEnabled: shadow
                    )
                    let png = try XCTUnwrap(output.pngDataPreservingBacking())
                    let decoded = try XCTUnwrap(NSBitmapImageRep(data: png)?.cgImage)
                    let original = try XCTUnwrap(source.cgImagePreservingBacking())
                    let margin = Int((padding * scale).rounded())
                    XCTAssertEqual(decoded.width, original.width + 2 * margin)
                    XCTAssertEqual(decoded.height, original.height + 2 * margin)
                    let before = try pixels(original)
                    let after = try pixels(decoded)
                    // The rounded corners intentionally alter edge pixels. The
                    // opaque interior, including text and 1px lines, must match.
                    let inset = Int(ceil(14 * scale))
                    var changed = 0
                    for y in inset..<(original.height - inset) {
                        for x in inset..<(original.width - inset) {
                            let a = (y * original.width + x) * 4
                            let b = ((y + margin) * decoded.width + x + margin) * 4
                            if before[a..<a+4] != after[b..<b+4] { changed += 1 }
                        }
                    }
                    XCTAssertEqual(changed, 0, "scale=\(scale), padding=\(padding), shadow=\(shadow)")
                    if scale == 2 && padding == 9.3 && shadow,
                       let directory = ProcessInfo.processInfo.environment["CLIP_PIXEL_ARTIFACTS"] {
                        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                        try source.pngDataPreservingBacking()?.write(to: URL(fileURLWithPath: directory + "/source.png"))
                        try png.write(to: URL(fileURLWithPath: directory + "/beautified.png"))
                    }
                }
            }
        }
    }

    private func makeSource(scale: CGFloat) throws -> NSImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 641, height: 359, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 641, height: 359))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for x in stride(from: 40, to: 600, by: 4) {
            context.fill(CGRect(x: x, y: 40, width: 1, height: 80))
        }
        for y in stride(from: 140, to: 200, by: 4) {
            context.fill(CGRect(x: 40, y: y, width: 560, height: 1))
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("1:1 像素清晰度测试 Abc 0123456789" as NSString).draw(
            at: CGPoint(x: 40, y: 240),
            withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black]
        )
        NSGraphicsContext.restoreGraphicsState()
        let image = try XCTUnwrap(context.makeImage())
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: 641 / scale, height: 359 / scale)
        let result = NSImage(size: rep.size)
        result.addRepresentation(rep)
        return result
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try XCTUnwrap(context.data)
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }
}
