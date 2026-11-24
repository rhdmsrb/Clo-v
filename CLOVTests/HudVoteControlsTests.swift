import XCTest
@testable import CLOV

final class HudVoteControlsTests: XCTestCase {
    func testLookCodePadsToTwoDigits() {
        XCTAssertEqual(HudStyle.lookCode(position: 2), "LOOK_02")
        XCTAssertEqual(HudStyle.lookCode(position: 12), "LOOK_12")
    }

    func testLookCodeNeverGoesNegative() {
        XCTAssertEqual(HudStyle.lookCode(position: -1), "LOOK_00")
    }

    func testPercentRoundsTheFraction() {
        XCTAssertEqual(HudStyle.percent(0), 0)
        XCTAssertEqual(HudStyle.percent(0.624), 62)
        XCTAssertEqual(HudStyle.percent(0.625), 63)
        XCTAssertEqual(HudStyle.percent(1), 100)
    }

    func testPercentClampsOutOfRangeFractions() {
        XCTAssertEqual(HudStyle.percent(-0.3), 0)
        XCTAssertEqual(HudStyle.percent(1.7), 100)
    }
}
