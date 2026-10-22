import XCTest
@testable import capcap

final class UpdateCheckerTests: XCTestCase {
    func testManualDebugCheckOffersLatestReleaseRegardlessOfVersionNumber() {
        for latest in ["1.7.15", "1.7.16", "1.7.17"] {
            XCTAssertTrue(UpdateChecker.shouldOfferRelease(
                latestVersion: latest,
                currentVersion: "1.7.16",
                manual: true,
                isDebugBuild: true
            ))
        }
    }

    func testAutomaticDebugCheckAndReleaseBuildStillCompareVersions() {
        for manual in [false, true] {
            for isDebugBuild in [false, true] where !(manual && isDebugBuild) {
                XCTAssertFalse(UpdateChecker.shouldOfferRelease(
                    latestVersion: "1.7.16",
                    currentVersion: "1.7.16",
                    manual: manual,
                    isDebugBuild: isDebugBuild
                ))
                XCTAssertTrue(UpdateChecker.shouldOfferRelease(
                    latestVersion: "1.7.17",
                    currentVersion: "1.7.16",
                    manual: manual,
                    isDebugBuild: isDebugBuild
                ))
            }
        }
    }
}
