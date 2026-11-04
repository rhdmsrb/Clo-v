import XCTest
@testable import CLOV

final class ExpiryTests: XCTestCase {
    func testNilExpiryNeverExpires() {
        XCTAssertFalse(isExpired(nil))
    }

    func testPastDateIsExpired() {
        XCTAssertTrue(isExpired(Date(timeIntervalSinceNow: -60)))
    }

    func testFutureDateIsNotExpired() {
        XCTAssertFalse(isExpired(Date(timeIntervalSinceNow: 3600)))
    }
}
