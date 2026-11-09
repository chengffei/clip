import AppKit
import XCTest
@testable import Clip

/// Temporary benchmark: peak footprint while stitching a long page.
/// Runs only with CLIP_SCROLL_BENCH=1.
final class ScrollMemoryBenchTests: XCTestCase {
    private func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576
    }

    private func makePage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var rng = SystemRandomNumberGenerator()
        var y = 10
        while y < height - 30 {
            let rowHeight = Int.random(in: 14...28, using: &rng)
            var x = 20
            while x < width - 100 {
                let w = Int.random(in: 30...180, using: &rng)
                ctx.setFillColor(CGColor(red: .random(in: 0...1, using: &rng), green: .random(in: 0...1, using: &rng),
                                         blue: .random(in: 0...1, using: &rng), alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: w, height: rowHeight - 4))
                x += w + Int.random(in: 10...40, using: &rng)
            }
            y += rowHeight + Int.random(in: 4...12, using: &rng)
        }
        return ctx.makeImage()!
    }

    func testPeakFootprintWhileStitching() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLIP_SCROLL_BENCH"] != nil)
        let width = 2000, frameHeight = 1800, frames = 30, step = 400
        let page = makePage(width: width, height: frameHeight + step * frames)
        let up = ProcessInfo.processInfo.environment["CLIP_SCROLL_BENCH_UP"] != nil
        var images: [NSImage] = []
        for i in 0..<frames {
            let offset = up ? step * (frames - 1 - i) : step * i
            let crop = page.cropping(to: CGRect(x: 0, y: offset, width: width, height: frameHeight))!
            // Materialise a private copy like the stream does.
            let ctx = CGContext(data: nil, width: width, height: frameHeight, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: frameHeight))
            images.append(NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: width / 2, height: frameHeight / 2)))
        }
        let before = footprintMB()
        var previews = 0
        var lastPreview: NSImage?
        let started = Date()
        let result = ScrollCapturer.stitchForTesting(images, tracking: true) { image in
            previews += 1
            lastPreview = image
        }
        let elapsed = Date().timeIntervalSince(started)
        let after = footprintMB()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let outDir = ProcessInfo.processInfo.environment["CLIP_SCROLL_BENCH_DIR"]
        if let outDir {
            if let preview = lastPreview, let cg = preview.cgImagePreservingBacking() {
                try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(up ? "preview-up.png" : "preview-down.png"))
            }
            if let stitched = result.image?.cgImagePreservingBacking() {
                try NSBitmapImageRep(cgImage: stitched).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(up ? "stitched-up.png" : "stitched-down.png"))
            }
        }
        // The stitched page must equal the source page row for row.
        if let stitched = result.image?.cgImagePreservingBacking() {
            let expectedHeight = frameHeight + step * (frames - 1)
            XCTAssertEqual(stitched.height, expectedHeight)
            XCTAssertEqual(stitched.width, width)
            let stitchedData = stitched.dataProvider!.data! as Data
            let pageData = page.dataProvider!.data! as Data
            var mismatches = 0
            for y in stride(from: 0, to: min(stitched.height, expectedHeight), by: 7) {
                for x in stride(from: 0, to: width, by: 13) {
                    let a = stitchedData[y * stitched.bytesPerRow + x * 4 + 1]
                    let b = pageData[y * page.bytesPerRow + x * 4 + 1]
                    if abs(Int(a) - Int(b)) > 2 { mismatches += 1 }
                }
            }
            XCTAssertEqual(mismatches, 0, "stitched page differs from source")
        }
        print(String(format: "BENCH up=%d accepted=%d stitched=%@ previews=%d previewPx=%@ before=%.0fMB after=%.0fMB delta=%.0fMB time=%.2fs",
                     up ? 1 : 0, result.accepted, result.image.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "nil",
                     previews, lastPreview.flatMap { $0.cgImagePreservingBacking() }.map { "\($0.width)x\($0.height)" } ?? "-",
                     before, after, after - before, elapsed))
    }
}
