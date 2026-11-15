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
    func testRatioIsStablePerIdAndFromTable() {
        let id = UUID()
        XCTAssertEqual(ExploreTileRatio.ratio(for: id), ExploreTileRatio.ratio(for: id))
        XCTAssertTrue(ExploreTileRatio.ratios.contains(ExploreTileRatio.ratio(for: id)))
    }

    func testRatiosVaryAcrossIds() {
        let distinct = Set((0..<64).map { _ in ExploreTileRatio.ratio(for: UUID()) })
        XCTAssertGreaterThan(distinct.count, 3)
    }

    func testRatioIgnoresPositionInList() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let first = ExploreTileRatio.ratio(for: id)
        _ = (0..<5).map { _ in ExploreTileRatio.ratio(for: UUID()) }
        XCTAssertEqual(ExploreTileRatio.ratio(for: id), first)
    }

    func testDisplayLikeCountHidesNilAndZero() {
        XCTAssertNil(PostCardContent.displayLikeCount(nil))
        XCTAssertNil(PostCardContent.displayLikeCount(0))
        XCTAssertEqual(PostCardContent.displayLikeCount(128), 128)
    }
}

final class ExploreFilterApplyTests: XCTestCase {
    private func item(tags: [String]? = nil, votes: Int = 0, age: TimeInterval = 0) -> FeedItemDTO {
        FeedItemDTO(id: UUID(), creatorId: UUID(), createdAt: Date(timeIntervalSince1970: 1_000_000 - age),
                    fitCheckPhotos: [], fitCheckVotes: [], fitCheckComments: [], tags: tags, voteCount: votes)
    }

    func testTagFilterKeepsOnlyMatchingCaseInsensitively() {
        let denim = item(tags: ["Denim", "Fall"]), plain = item(), other = item(tags: ["Suit"])
        var filter = ExploreFilter()
        filter.tag = "DENIM"
        XCTAssertEqual(filter.apply(to: [plain, denim, other]).map(\.id), [denim.id])
    }

    func testMostVotedSortsByTotalVotesDescending() {
        let low = item(votes: 1), high = item(votes: 9), mid = item(votes: 4)
        var filter = ExploreFilter()
        filter.sort = .mostVoted
        XCTAssertEqual(filter.apply(to: [low, high, mid]).map(\.id), [high.id, mid.id, low.id])
    }

    func testMostVotedTieBreaksByNewest() {
        let older = item(votes: 3, age: 100), newer = item(votes: 3, age: 0)
        var filter = ExploreFilter()
        filter.sort = .mostVoted
        XCTAssertEqual(filter.apply(to: [older, newer]).map(\.id), [newer.id, older.id])
    }

    func testNewestSortsByCreatedAtDescending() {
        let older = item(age: 100), newer = item(age: 0)
        XCTAssertEqual(ExploreFilter().apply(to: [older, newer]).map(\.id), [newer.id, older.id])
    }

    func testTagAndMostVotedCompose() {
        let a = item(tags: ["x"], votes: 2), b = item(tags: ["x"], votes: 8), c = item(tags: ["y"], votes: 99)
        var filter = ExploreFilter()
        filter.tag = "x"; filter.sort = .mostVoted
        XCTAssertEqual(filter.apply(to: [a, c, b]).map(\.id), [b.id, a.id])
    }
}
