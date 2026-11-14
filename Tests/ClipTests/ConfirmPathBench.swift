import AppKit
import XCTest
@testable import Clip

/// Times the work between "confirm" and the image landing on the clipboard,
/// on a desktop-like 3024x1964 image (a live screen capture when the test
/// host has Screen Recording permission, synthetic otherwise):
/// `CLIP_CONFIRM_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter ConfirmPathBench`
@MainActor
final class ConfirmPathBench: XCTestCase {
    private var enabled: Bool { ProcessInfo.processInfo.environment["CLIP_CONFIRM_BENCH"] != nil }

    static func ms(_ block: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try block()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    }

    static func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }

    /// A busy desktop-like image: text-ish stripes, gradients and flat areas.
    static func desktopLikeImage(width: Int = 3024, height: Int = 1964) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<40 {
            let r = CGRect(x: Int.random(in: 0..<width, using: &rng), y: Int.random(in: 0..<height, using: &rng),
                           width: Int.random(in: 100..<900, using: &rng), height: Int.random(in: 60..<600, using: &rng))
            ctx.setFillColor(CGColor(red: .random(in: 0...1), green: .random(in: 0...1), blue: .random(in: 0...1), alpha: 1))
            ctx.fill(r)
        }
        // "Text": many short dark runs.
        ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))
        for y in stride(from: 40, to: height - 40, by: 34) {
            var x = 60
            while x < width - 200 {
                let w = Int.random(in: 8..<70, using: &rng)
                ctx.fill(CGRect(x: x, y: y, width: w, height: 18))
                x += w + Int.random(in: 6..<22, using: &rng)
            }
        }
        return ctx.makeImage()!
    }

    static func sourceImage() async -> CGImage {
        if ProcessInfo.processInfo.environment["CLIP_LIVE_CAPTURE"] != nil,
           let screen = NSScreen.main,
           let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            let target = ScreenSnapshotTarget(displayID: displayID, bounds: CGDisplayBounds(displayID),
                                              scale: screen.backingScaleFactor)
            let image: CGImage? = await withCheckedContinuation { continuation in
                var resumed = false
                ScreenSnapshotProvider.shared.capture(targets: [target]) { event in
                    guard !resumed else { return }
                    switch event {
                    case .image(_, let image): resumed = true; continuation.resume(returning: image)
                    case .failure, .finished: resumed = true; continuation.resume(returning: nil)
                    }
                }
            }
            if let image { return image }
        }
        return desktopLikeImage()
    }

    func testClipboardEncode() async throws {
        guard enabled else { return }
        let full = await Self.sourceImage()
        let regions: [(String, CGRect)] = [
            ("full 3024x1964", CGRect(x: 0, y: 0, width: full.width, height: full.height)),
            ("half 1600x1000", CGRect(x: 200, y: 200, width: 1600, height: 1000)),
            ("small 600x400", CGRect(x: 400, y: 300, width: 600, height: 400)),
        ]
        for (name, rect) in regions {
            let cg = try XCTUnwrap(full.cropping(to: rect))
            let image = NSImage(cgImage: cg, size: NSSize(width: rect.width / 2, height: rect.height / 2))
            var total: [Double] = []
            var bytes = 0
            for _ in 0..<5 {
                let start = DispatchTime.now().uptimeNanoseconds
                let output: EncodedClipboardImageOutput = try await withCheckedThrowingContinuation { c in
                    ImageOutputEncoder.encodeClipboardAsync(image: image, quality: .original) { c.resume(with: $0) }
                }
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("clip.bench.\(UUID().uuidString)"))
                pasteboard.clearContents()
                pasteboard.setData(output.primary.data, forType: .png)
                if let tiff = output.tiffData { pasteboard.setData(tiff, forType: .tiff) }
                total.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                bytes = output.primary.data.count + (output.tiffData?.count ?? 0)
                pasteboard.releaseGlobally()
            }
            print(String(format: "CONFIRMBENCH clipboard %@ p50=%.0fms min=%.0fms bytes=%.1fMB",
                         name, Self.median(total), total.min()!, Double(bytes) / 1e6))
        }
    }
}
