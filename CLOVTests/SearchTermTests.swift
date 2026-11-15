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

final class ExploreTileRatioTests: XCTestCase {
    func testRatiosAreDeterministicAndVaried() {
        XCTAssertEqual(ExploreTileRatio.ratio(forIndex: 3), ExploreTileRatio.ratio(forIndex: 3))
        XCTAssertGreaterThan(Set((0..<8).map { ExploreTileRatio.ratio(forIndex: $0) }).count, 3)
    }

    func testIndexWrapsAndNegativeIsSafe() {
        let count = ExploreTileRatio.ratios.count
        XCTAssertEqual(ExploreTileRatio.ratio(forIndex: count), ExploreTileRatio.ratio(forIndex: 0))
        XCTAssertEqual(ExploreTileRatio.ratio(forIndex: -1), ExploreTileRatio.ratios[count - 1])
    }

    func testDisplayLikeCountHidesNilAndZero() {
        XCTAssertNil(PostCardContent.displayLikeCount(nil))
        XCTAssertNil(PostCardContent.displayLikeCount(0))
        XCTAssertEqual(PostCardContent.displayLikeCount(128), 128)
    }
}
