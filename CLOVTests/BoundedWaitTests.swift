import XCTest
@testable import CLOV

final class BoundedWaitTests: XCTestCase {
    func testReturnsPromptlyWhenOperationFinishesFirst() async {
        let started = ContinuousClock.now
        await runBounded(timeout: .seconds(5)) {}
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(1))
    }

    func testReturnsAtTimeoutWhenOperationIsSlow() async {
        let started = ContinuousClock.now
        await runBounded(timeout: .milliseconds(200)) {
            try? await Task.sleep(for: .seconds(30))
        }
        let elapsed = ContinuousClock.now - started
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(150))
        XCTAssertLessThan(elapsed, .seconds(5))
    }

    /// A request that never checks for cancellation must still not block logout.
    func testReturnsAtTimeoutWhenOperationIgnoresCancellation() async {
        let started = ContinuousClock.now
        await runBounded(timeout: .milliseconds(200)) {
            let deadline = ContinuousClock.now + .seconds(3)
            while ContinuousClock.now < deadline {
                await Task.yield()
            }
        }
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(2))
    }

    func testCancelsOperationOnTimeout() async {
        let cancelled = expectation(description: "operation saw cancellation")
        await runBounded(timeout: .milliseconds(100)) {
            do { try await Task.sleep(for: .seconds(30)) }
            catch { cancelled.fulfill() }
        }
        await fulfillment(of: [cancelled], timeout: 2)
    }

    func testRunsTheOperation() async {
        let ran = expectation(description: "ran")
        await runBounded(timeout: .seconds(5)) { ran.fulfill() }
        await fulfillment(of: [ran], timeout: 2)
    }
}
