import XCTest
@testable import Clip

final class UpdateCheckerTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("0.5.0", than: "0.4.0"))
        XCTAssertTrue(UpdateChecker.isNewer("0.10.0", than: "0.9.1"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0", than: "0.99.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.4.0", than: "0.4.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.4", than: "0.4.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.3.9", than: "0.4.0"))
    }

    func testReadsVersionFromReleaseRedirect() throws {
        let url = try XCTUnwrap(URL(string: "https://github.com/chengffei/clip/releases/tag/v0.5.0"))
        XCTAssertEqual(UpdateChecker.release(fromTagURL: url)?.version, "0.5.0")
        XCTAssertNil(UpdateChecker.release(fromTagURL: UpdateChecker.releasesPage), "no redirect means no release")
    }

    func testReadsVersionFromJSDelivr() {
        let json = #"{"type": "gh", "name": "chengffei/clip", "version": "0.5.0"}"#
        XCTAssertEqual(UpdateChecker.version(fromJSDelivr: Data(json.utf8)), "0.5.0")
        XCTAssertNil(UpdateChecker.version(fromJSDelivr: Data(#"{"version": null}"#.utf8)))
        XCTAssertEqual(UpdateChecker.release(for: "0.5.0").pageURL.lastPathComponent, "v0.5.0")
    }
}
