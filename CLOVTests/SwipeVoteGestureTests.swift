import XCTest
@testable import CLOV

final class SwipeVoteGestureTests: XCTestCase {
    private let commit = SwipeVoteGesture.commitDistance

    func testLongRightSwipeVotesWhenVotingIsOpen() {
        XCTAssertEqual(SwipeVoteGesture.action(for: CGSize(width: commit + 1, height: 5), canVote: true), .vote)
    }

    func testRightSwipeOnlyBrowsesBackWhenVotingIsClosed() {
        XCTAssertEqual(SwipeVoteGesture.action(for: CGSize(width: commit + 1, height: 5), canVote: false), .previousLook)
    }

    func testLongLeftSwipeShowsNextLook() {
        XCTAssertEqual(SwipeVoteGesture.action(for: CGSize(width: -(commit + 1), height: 0), canVote: true), .nextLook)
    }

    func testShortSwipeDoesNothing() {
        XCTAssertEqual(SwipeVoteGesture.action(for: CGSize(width: commit - 1, height: 0), canVote: true), .none)
    }

    func testMostlyVerticalDragIsLeftToThePager() {
        XCTAssertEqual(SwipeVoteGesture.action(for: CGSize(width: commit + 20, height: commit * 2), canVote: true), .none)
        XCTAssertEqual(SwipeVoteGesture.progress(for: CGSize(width: 40, height: 200)), 0)
    }

    func testProgressScalesWithDistanceAndIsClamped() {
        XCTAssertEqual(SwipeVoteGesture.progress(for: CGSize(width: commit / 2, height: 0)), 0.5, accuracy: 0.001)
        XCTAssertEqual(SwipeVoteGesture.progress(for: CGSize(width: commit * 3, height: 0)), 1)
        XCTAssertEqual(SwipeVoteGesture.progress(for: CGSize(width: -commit * 3, height: 0)), -1)
    }

    func testLookIndexWrapsInBothDirections() {
        XCTAssertEqual(SwipeVoteGesture.index(after: 1, count: 2, step: 1), 0)
        XCTAssertEqual(SwipeVoteGesture.index(after: 0, count: 4, step: -1), 3)
        XCTAssertEqual(SwipeVoteGesture.index(after: 0, count: 0, step: 1), 0)
    }
}
