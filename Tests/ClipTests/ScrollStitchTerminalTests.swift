import AppKit
import XCTest
@testable import Clip

/// Terminal-like pages (dark background, monospaced lines, uneven scroll steps)
/// once stitched with seams several pixels off, cutting lines in half
/// (2026-10-28). The stitched result must match the page pixel for pixel.
final class ScrollStitchTerminalTests: XCTestCase {
    private let width = 760
    private let frameHeight = 908
    private let lineHeight = 34

    func testUnevenScrollStepsStitchExactly() throws {
        let shifts = [510, 442, 170, 680, 578, 238]
        let pageHeight = frameHeight + shifts.reduce(0, +)
        let page = makePage(height: pageHeight)

        var frames: [NSImage] = []
        var top = 0
        frames.append(slice(page, top: top))
        for shift in shifts {
            top += shift
            frames.append(slice(page, top: top))
        }

        let result = ScrollCapturer.stitchForTesting(frames)
        XCTAssertEqual(result.accepted, frames.count)
        let stitched = try XCTUnwrap(result.image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(stitched.height, pageHeight)
        XCTAssertEqual(rowMismatches(stitched, page), 0, "stitched rows differ from the page")
    }

    /// Scrolling faster than the polls leaves no overlap; that frame must be
    /// turned away instead of spliced in, and capture resumes once frames
    /// overlap again.
    func testFrameWithoutOverlapIsRejected() throws {
        let page = makePage(height: 2400)
        let frames = [slice(page, top: 0), slice(page, top: 1200), slice(page, top: 500)]
        let result = ScrollCapturer.stitchForTesting(frames)
        XCTAssertEqual(result.accepted, 2)
        let stitched = try XCTUnwrap(result.image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let expected = try XCTUnwrap(page.cropping(to: CGRect(x: 0, y: 0, width: width, height: frameHeight + 500)))
        XCTAssertEqual(rowMismatches(stitched, expected), 0)
    }

    // MARK: - Fixtures

    private func makePage(height: Int) -> CGImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let words = ["release", "dist/Clip-0.3.0.dmg", "scroll capture", "overlap", "gh auth switch",
                     "shasum -a 256", "README.zh-CN.md", "Finder", "background.tiff", "commit", "push"]
        var seed: UInt64 = 7
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed >> 33)
        }
        var y = height - lineHeight
        var line = 0
        while y > 0 {
            line += 1
            if next() % 5 != 0 {
                let text = (0..<(1 + next() % 5)).map { _ in words[next() % words.count] }.joined(separator: " ")
                NSString(string: "\(line) \(text)").draw(at: NSPoint(x: 12 + next() % 40, y: y + 6), withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .regular),
                    .foregroundColor: NSColor(white: 0.85, alpha: 1),
                ])
            }
            y -= lineHeight
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    private func slice(_ page: CGImage, top: Int) -> NSImage {
        let cg = page.cropping(to: CGRect(x: 0, y: top, width: width, height: frameHeight))!
        return NSImage(cgImage: cg, size: NSSize(width: width / 2, height: frameHeight / 2))
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    private func rowMismatches(_ lhs: CGImage, _ rhs: CGImage) -> Int {
        guard lhs.width == rhs.width, lhs.height == rhs.height else { return Int.max }
        let a = rgba(lhs), b = rgba(rhs)
        let stride = lhs.width * 4
        var mismatches = 0
        for row in 0..<lhs.height {
            var diff = 0
            for i in (row * stride)..<((row + 1) * stride) { diff += abs(Int(a[i]) - Int(b[i])) }
            if diff > lhs.width * 2 { mismatches += 1 }
        }
        return mismatches
    }
}
