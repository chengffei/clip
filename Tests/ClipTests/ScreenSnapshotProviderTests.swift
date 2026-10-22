import CoreGraphics
import XCTest
@testable import capcap

final class ScreenSnapshotProviderTests: XCTestCase {
    func testFiveKSnapshotUsesSingleFrameQueue() {
        let target = ScreenSnapshotTarget(
            displayID: 1,
            bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            scale: 2
        )

        let configuration = ScreenSnapshotProvider.makeStreamConfiguration(for: target)

        XCTAssertEqual(configuration.width, 5120)
        XCTAssertEqual(configuration.height, 2880)
        XCTAssertEqual(configuration.queueDepth, 1)
        XCTAssertFalse(configuration.capturesAudio)
        XCTAssertFalse(configuration.showsCursor)
        XCTAssertFalse(configuration.ignoreShadowsDisplay)
        XCTAssertFalse(configuration.ignoreShadowsSingleWindow)
        XCTAssertEqual(configuration.captureResolution, .best)
    }
}
