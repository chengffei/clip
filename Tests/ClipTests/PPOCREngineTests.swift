import AppKit
import XCTest
@testable import Clip

/// Runs the bundled PP-OCRv6 pipeline over research/ocr-bench/set when it is
/// present (not in git) and prints accuracy for comparison with RapidOCR.
final class PPOCREngineTests: XCTestCase {
    func testRecognizesRenderedLine() throws {
        let image = try XCTUnwrap(Self.render("储能系统今日放电量为 12.6 kWh"))
        let lines = try PPOCREngine.shared.recognize(image)
        XCTAssertEqual(lines.map(\.text).joined().filter { !$0.isWhitespace }, "储能系统今日放电量为12.6kWh")
        let box = try XCTUnwrap(lines.first?.boundingBox)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.01, dy: -0.01).contains(box))
    }

    func testBenchmarkSet() throws {
        guard let dir = ProcessInfo.processInfo.environment["CLIP_OCR_BENCH_SET"] else { return }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".png") }.sorted()
        var total = 0.0
        for file in files {
            let image = try XCTUnwrap(NSImage(contentsOfFile: "\(dir)/\(file)")?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let truth = try String(contentsOfFile: "\(dir)/\(file.dropLast(4)).txt", encoding: .utf8)
            let start = Date()
            let text = try PPOCREngine.shared.recognize(image).map(\.text).joined(separator: "\n")
            let score = Self.accuracy(text, truth)
            total += score
            print(String(format: "PPOCR %@ %.2f %.2fs %@", file, score, Date().timeIntervalSince(start), text.replacingOccurrences(of: "\n", with: " / ")))
        }
        print(String(format: "PPOCR average %.3f over %d", total / Double(files.count), files.count))
    }

    static func accuracy(_ got: String, _ truth: String) -> Double {
        func norm(_ s: String) -> [Character] { Array(s.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace }) }
        let a = norm(got), b = norm(truth)
        guard !b.isEmpty else { return a.isEmpty ? 1 : 0 }
        var prev = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count { cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)) }
            prev = cur
        }
        return max(0, 1 - Double(a.isEmpty ? b.count : prev[b.count]) / Double(b.count))
    }

    static func render(_ text: String) -> CGImage? {
        let font = NSFont.systemFont(ofSize: 26)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        let size = string.size()
        let w = Int(size.width) + 12, h = Int(size.height) + 8
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        string.draw(at: NSPoint(x: 6, y: 4))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
