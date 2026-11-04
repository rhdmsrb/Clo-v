import XCTest
@testable import CLOV

final class SearchTermTests: XCTestCase {
    func testKeepsPlainNicknameAndAccountCode() {
        XCTAssertEqual(SearchTerm.sanitized("Jane_Doe-9.x"), "Jane_Doe-9.x")
    }

    func testKeepsSpacesAndNonLatinLetters() {
        XCTAssertEqual(SearchTerm.sanitized("김 민준"), "김 민준")
    }

    func testStripsFilterSyntaxCharacters() {
        XCTAssertEqual(SearchTerm.sanitized("x,id.neq.0"), "xid.neq.0")
        XCTAssertEqual(SearchTerm.sanitized("a),(b"), "ab")
        XCTAssertEqual(SearchTerm.sanitized("%*\\\"'"), "")
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(SearchTerm.sanitized("  amy \n"), "amy")
    }

    func testCapsLength() {
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(SearchTerm.sanitized(long).count, SearchTerm.maxLength)
    }
}

final class LikeEscapeTests: XCTestCase {
    func testEscapesLikeWildcardsAndBackslash() {
        XCTAssertEqual(SearchTerm.likeEscaped("100%_sure\\"), "100\\%\\_sure\\\\")
    }

    func testLeavesPlainTextAlone() {
        XCTAssertEqual(SearchTerm.likeEscaped("summer fit"), "summer fit")
    }
}
