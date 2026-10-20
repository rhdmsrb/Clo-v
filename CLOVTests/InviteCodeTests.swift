import XCTest
@testable import CLOV

final class InviteCodeTests: XCTestCase {
    func testDefaultLengthIsSix() {
        XCTAssertEqual(InviteCode.generate().count, 6)
    }

    func testHonorsRequestedLength() {
        XCTAssertEqual(InviteCode.generate(length: 10).count, 10)
        XCTAssertEqual(InviteCode.generate(length: 0), "")
    }

    func testNeverUsesAmbiguousCharacters() {
        let ambiguous = Set("01OI")
        for _ in 0..<500 {
            XCTAssertTrue(Set(InviteCode.generate(length: 12)).isDisjoint(with: ambiguous))
        }
    }

    func testUsesOnlyUppercaseLettersAndDigits() {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        for _ in 0..<200 {
            let code = InviteCode.generate()
            XCTAssertTrue(code.unicodeScalars.allSatisfy(allowed.contains), code)
        }
    }
}
