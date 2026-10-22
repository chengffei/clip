import XCTest
@testable import capcap

final class AsyncDeadlineTests: XCTestCase {
    func testReturnsValueAndPropagatesError() async throws {
        let value = try await AsyncDeadline.run(seconds: 1) { 42 }
        XCTAssertEqual(value, 42)
        do {
            let _: Int = try await AsyncDeadline.run(seconds: 1) { throw Failure.expected }
            XCTFail("Expected operation error")
        } catch { XCTAssertTrue(error is Failure) }
    }

    func testDeadlineDoesNotWaitForUncooperativeOperationAndIgnoresLateResult() async {
        let lateCompletion = expectation(description: "Late operation finishes safely")
        let started = Date()
        do {
            let _: Int = try await AsyncDeadline.run(seconds: 0.02) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                        continuation.resume(returning: 42)
                        lateCompletion.fulfill()
                    }
                }
            }
            XCTFail("Expected deadline")
        } catch { XCTAssertTrue(error is AsyncDeadline.TimedOut) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.25)
        await fulfillment(of: [lateCompletion], timeout: 1)
    }

    func testCancellationResumesCaller() async {
        let task = Task {
            try await AsyncDeadline.run(seconds: 10) {
                try await Task.sleep(for: .seconds(10))
                return 42
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    private enum Failure: Error { case expected }
}
