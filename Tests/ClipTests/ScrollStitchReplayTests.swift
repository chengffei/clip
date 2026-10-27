import AppKit
import XCTest
@testable import Clip

/// Replays frames saved by a real capture (CLIP_SCROLL_REPLAY = folder with
/// 1-prev.png, 1-cur.png …) through the accept and stitch logic.
final class ScrollStitchReplayTests: XCTestCase {
    func testReplaySavedFrames() throws {
        guard let dir = ProcessInfo.processInfo.environment["CLIP_SCROLL_REPLAY"] else { return }
        let names = ["1-prev.png", "1-cur.png", "2-cur.png", "3-cur.png"]
        let images = try names.map { try XCTUnwrap(NSImage(contentsOfFile: "\(dir)/\($0)")) }
        let result = ScrollCapturer.stitchForTesting(images)
        let cg = try XCTUnwrap(result.image?.cgImagePreservingBacking())
        print("REPLAY accepted=\(result.accepted) stitched=\(cg.width)x\(cg.height)")
        if let out = ProcessInfo.processInfo.environment["CLIP_SNAPSHOT_DIR"] {
            try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(out)/replay-stitched.png"))
        }
        XCTAssertGreaterThan(result.accepted, 1)
    }
}
