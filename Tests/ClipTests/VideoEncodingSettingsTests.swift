import CoreGraphics
import XCTest
@testable import capcap

/// `VideoEncodingSettings.evenDimensions` must round odd inputs UP to the next
/// even integer (H.264 requires even pixel dimensions; rounding down would
/// capture a frame smaller than the source). These cases pin that contract.
final class VideoEncodingSettingsTests: XCTestCase {

    // MARK: Odd inputs round up to the next even integer

    func testOddDimensionsRoundUp() {
        let result = VideoEncodingSettings.evenDimensions(width: 1921, height: 1081)
        XCTAssertEqual(result.0, 1922, "odd width 1921 must round up to 1922, not down to 1920")
        XCTAssertEqual(result.1, 1082, "odd height 1081 must round up to 1082, not down to 1080")
    }

    func testLargeOddDimensionsRoundUp() {
        let result = VideoEncodingSettings.evenDimensions(width: 3839, height: 2159)
        XCTAssertEqual(result.0, 3840)
        XCTAssertEqual(result.1, 2160)
    }

    // MARK: Even inputs are unchanged

    func testEvenDimensionsAreUnchanged() {
        let a = VideoEncodingSettings.evenDimensions(width: 1920, height: 1080)
        XCTAssertEqual(a.0, 1920)
        XCTAssertEqual(a.1, 1080)

        let b = VideoEncodingSettings.evenDimensions(width: 1922, height: 1082)
        XCTAssertEqual(b.0, 1922)
        XCTAssertEqual(b.1, 1082)
    }

    // MARK: Fractional inputs ceiling up, then round odd up

    func testFractionalCeilsThenRoundsOddUp() {
        // 1922.5 ceilings to 1923 (odd), which then rounds up to 1924
        let result = VideoEncodingSettings.evenDimensions(width: 1922.5, height: 1082.5)
        XCTAssertEqual(result.0, 1924, "1922.5 ceilings to 1923 then rounds up to 1924")
        XCTAssertEqual(result.1, 1084, "1082.5 ceilings to 1083 then rounds up to 1084")
    }

    func testFractionalThatCeilsToEvenIsUnchanged() {
        // 1921.4 ceilings to 1922 (even) and stays; 1079.1 ceilings to 1080 (even) and stays
        let result = VideoEncodingSettings.evenDimensions(width: 1921.4, height: 1079.1)
        XCTAssertEqual(result.0, 1922)
        XCTAssertEqual(result.1, 1080)
    }

    // MARK: Tiny / sub-minimum inputs honor the 2px floor

    func testTinyOddRoundsUpAboveTwoPixelFloor() {
        let result = VideoEncodingSettings.evenDimensions(width: 3, height: 3)
        XCTAssertEqual(result.0, 4, "odd 3 rounds up to 4, above the 2px floor")
        XCTAssertEqual(result.1, 4)
    }

    func testMinimumFloorIsTwoPixels() {
        let one = VideoEncodingSettings.evenDimensions(width: 1, height: 1)
        XCTAssertEqual(one.0, 2)
        XCTAssertEqual(one.1, 2)

        let zero = VideoEncodingSettings.evenDimensions(width: 0, height: 0)
        XCTAssertEqual(zero.0, 2)
        XCTAssertEqual(zero.1, 2)
    }
}
