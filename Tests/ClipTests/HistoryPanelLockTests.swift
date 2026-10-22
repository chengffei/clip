import XCTest
@testable import capcap

final class HistoryPanelLockTests: XCTestCase {
    func testUnlockedPanelAllowsAutomaticDismissal() {
        XCTAssertTrue(HistoryPanelDismissalPolicy.shouldDismissAutomatically(isLocked: false))
    }

    func testLockedPanelBlocksAutomaticDismissal() {
        XCTAssertFalse(HistoryPanelDismissalPolicy.shouldDismissAutomatically(isLocked: true))
    }
}
