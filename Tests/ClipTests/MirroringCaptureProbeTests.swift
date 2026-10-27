import AppKit
import XCTest
@testable import Clip

/// Probe for a specific on-screen region (CLIP_PROBE_RECT="x,y,w,h" in CG
/// global points). Prints what Clip's capture path returns there.
final class MirroringCaptureProbeTests: XCTestCase {
    func testProbeRegion() throws {
        guard let spec = ProcessInfo.processInfo.environment["CLIP_PROBE_RECT"] else { return }
        let v = spec.split(separator: ",").compactMap { Double($0) }
        let rect = CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
        let screen = try XCTUnwrap(NSScreen.main)
        let image = ScreenCapturer.capture(rect: rect, screen: screen, timeout: 3)
        print("PROBE capture image=\(image.map { "\($0.size)" } ?? "nil")")
        if let cg = image?.cgImagePreservingBacking() {
            print("PROBE cg \(cg.width)x\(cg.height) bpc=\(cg.bitsPerComponent) bpp=\(cg.bitsPerPixel) alpha=\(cg.alphaInfo.rawValue) info=\(cg.bitmapInfo.rawValue) space=\(cg.colorSpace?.name as String? ?? "nil")")
            let r = image?.bitmapImageRepPreservingBacking()
            print("PROBE cg.colorSpace nil? \(cg.colorSpace == nil) model=\(cg.colorSpace.map { "\($0.model.rawValue)" } ?? "-") rep.bitmapData nil? \(r?.bitmapData == nil) rep.cgImage.colorSpace nil? \(r?.cgImage?.colorSpace == nil)")
            print("PROBE rep=\(image?.bitmapImageRepPreservingBacking().map { "bps=\($0.bitsPerSample) spp=\($0.samplesPerPixel) fmt=\($0.bitmapFormat.rawValue)" } ?? "nil")")
        }
        let capturer = ScrollCapturer(rect: rect, screen: screen)
        print("PROBE scroll capturer first frame=\(capturer.frameCount)")
    }
}
