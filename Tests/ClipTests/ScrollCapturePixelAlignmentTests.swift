import XCTest
@testable import Clip

final class ScrollCapturePixelAlignmentTests: XCTestCase {
    func testFractionalRectSnapsOutwardToWholePixels() {
        let rect = CGRect(x: 100.3, y: 50.6, width: 1012.6, height: 377.2)
        let aligned = ScrollCapturer.pixelAligned(rect, scale: 2)
        for value in [aligned.minX, aligned.minY, aligned.width, aligned.height] {
            XCTAssertEqual((value * 2).rounded(), value * 2, accuracy: 1e-9)
        }
        XCTAssertTrue(aligned.contains(rect))
        XCTAssertLessThanOrEqual(aligned.width - rect.width, 1)
    }

    func testAlignedRectIsUnchanged() {
        let rect = CGRect(x: 10.5, y: 20, width: 300.5, height: 200)
        XCTAssertEqual(ScrollCapturer.pixelAligned(rect, scale: 2), rect)
    }
}
