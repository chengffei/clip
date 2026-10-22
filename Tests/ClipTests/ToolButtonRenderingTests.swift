import AppKit
import XCTest
@testable import capcap

@MainActor
final class ToolButtonRenderingTests: XCTestCase {
    func testSymbolsKeepTheirFullHeightAtBothBackingScales() throws {
        _ = NSApplication.shared
        for symbol in ["square.and.arrow.up", "pin", "text.viewfinder", "arrow.uturn.backward"] {
            let button = ToolButton(
                frame: NSRect(x: 0, y: 0, width: 40, height: 40),
                symbolName: symbol, normalColor: .black, selectedColor: .black,
                symbolPointSize: ToolbarView.symbolPointSize
            )
            let image = try XCTUnwrap(button.image)
            for scale in [1, 2] {
                let actual = try render(scale: scale) { button.draw(button.bounds) }
                let reference = try render(scale: scale) {
                    image.draw(in: NSRect(
                        x: (40 - image.size.width) / 2,
                        y: (40 - image.size.height) / 2,
                        width: image.size.width, height: image.size.height
                    ))
                }
                XCTAssertEqual(inkHeight(actual), inkHeight(reference), accuracy: 2,
                               "\(symbol) at \(scale)x must retain the full symbol, including ascenders and descenders")
            }
        }
    }

    private func render(scale: Int, draw: () -> Void) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 40 * scale, pixelsHigh: 40 * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = NSSize(width: 40, height: 40)
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        draw()
        return bitmap
    }

    private func inkHeight(_ bitmap: NSBitmapImageRep) -> Double {
        let rows = (0..<bitmap.pixelsHigh).filter { y in
            (0..<bitmap.pixelsWide).contains { x in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1
            }
        }
        guard let first = rows.first, let last = rows.last else { return 0 }
        return Double(last - first + 1)
    }
}
