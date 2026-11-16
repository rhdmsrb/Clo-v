import XCTest
@testable import CLOV

final class VoteRevealTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    func testPercentRoundsAndGuardsZeroTotal() {
        XCTAssertEqual(VoteReveal.percent(count: 1, total: 3), 33)
        XCTAssertEqual(VoteReveal.percent(count: 2, total: 3), 67)
        XCTAssertEqual(VoteReveal.percent(count: 0, total: 0), 0)
        XCTAssertEqual(VoteReveal.percent(count: -1, total: 5), 0)
    }

    func testLeadingIsTheTopPhoto() {
        XCTAssertEqual(VoteReveal.leadingIds(photoIds: [a, b], counts: [a: 3, b: 1]), [a])
    }

    func testNoLeaderWithoutVotes() {
        XCTAssertTrue(VoteReveal.leadingIds(photoIds: [a, b], counts: [:]).isEmpty)
    }

    func testFullTieHasNoLeaderButPartialTieHasTwo() {
        XCTAssertTrue(VoteReveal.leadingIds(photoIds: [a, b], counts: [a: 2, b: 2]).isEmpty)
        XCTAssertEqual(VoteReveal.leadingIds(photoIds: [a, b, c], counts: [a: 2, b: 2, c: 1]), [a, b])
    }

    func testSinglePhotoWithVotesLeads() {
        XCTAssertEqual(VoteReveal.leadingIds(photoIds: [a], counts: [a: 1]), [a])
    }

    func testCelebratesOnlyWhenBackingLeaderWithEnoughVotes() {
        let counts = [a: 3, b: 1]
        XCTAssertTrue(VoteReveal.shouldCelebrate(myVote: a, photoIds: [a, b], counts: counts, total: 4))
        XCTAssertFalse(VoteReveal.shouldCelebrate(myVote: b, photoIds: [a, b], counts: counts, total: 4))
        XCTAssertFalse(VoteReveal.shouldCelebrate(myVote: nil, photoIds: [a, b], counts: counts, total: 4))
        XCTAssertFalse(VoteReveal.shouldCelebrate(myVote: a, photoIds: [a, b], counts: [a: 1], total: 1))
    }

    func testRetargetAnimatesOnlyInsideTheRevealWindow() {
        let start = Date()
        XCTAssertTrue(VoteReveal.shouldAnimateRetarget(since: start, now: start.addingTimeInterval(0.5)))
        XCTAssertFalse(VoteReveal.shouldAnimateRetarget(since: start, now: start.addingTimeInterval(5)))
        XCTAssertFalse(VoteReveal.shouldAnimateRetarget(since: nil))
    }
}
