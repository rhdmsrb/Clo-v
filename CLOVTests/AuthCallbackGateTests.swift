import XCTest
@testable import CLOV

final class AuthCallbackGateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var clock: Date!

    override func setUp() {
        defaults = UserDefaults(suiteName: "AuthCallbackGateTests")!
        defaults.removePersistentDomain(forName: "AuthCallbackGateTests")
        clock = Date(timeIntervalSince1970: 1_000_000)
    }

    private func makeGate() -> AuthCallbackGate {
        AuthCallbackGate(defaults: defaults, now: { self.clock })
    }

    func testRejectsCallbackWhenNoResetWasRequested() {
        XCTAssertFalse(makeGate().consume())
    }

    func testAcceptsCallbackOnceAfterResetRequested() {
        let gate = makeGate()
        gate.markResetRequested()
        XCTAssertTrue(gate.consume())
        XCTAssertFalse(gate.consume())
    }

    func testRejectsCallbackAfterValidityWindow() {
        let gate = makeGate()
        gate.markResetRequested()
        clock = clock.addingTimeInterval(AuthCallbackGate.validity + 1)
        XCTAssertFalse(gate.consume())
    }
}

final class SafeLinkTests: XCTestCase {
    func testAcceptsHttpsURL() {
        XCTAssertNotNil(SafeLink.httpsURL("https://creativecommons.org/licenses/by/4.0/"))
    }

    func testRejectsNonHttpsSchemesAndNil() {
        for raw in ["tel:+15555550100", "sms:123", "http://example.com", "javascript:alert(1)", "https://", ""] {
            XCTAssertNil(SafeLink.httpsURL(raw), raw)
        }
        XCTAssertNil(SafeLink.httpsURL(nil))
    }
}
