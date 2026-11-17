import XCTest
@testable import CLOV

/// Rules for voting on the feed post card itself: keeping the feed's copy of a
/// post in step with the viewer's vote, and the vote button wording.
final class FeedCardVoteTests: XCTestCase {
    private let viewer = UUID()
    private let photoA = UUID()
    private let photoB = UUID()

    private func item(votes: [VoteRef] = [], voteCount: Int? = nil) -> FeedItemDTO {
        FeedItemDTO(id: UUID(), creatorId: UUID(), createdAt: Date(), fitCheckPhotos: [],
                    fitCheckVotes: votes, fitCheckComments: [], voteCount: voteCount)
    }

    // MARK: applyingVote

    func testApplyingVoteAddsViewersRowAndBumpsCount() {
        let result = PostCardContent.applyingVote(photoA, voterId: viewer, to: item(voteCount: 4))

        XCTAssertEqual(result.ownVote(voterId: viewer), photoA)
        XCTAssertEqual(result.voteCount, 5)
    }

    func testApplyingVoteReplacesViewersExistingRowWithoutChangingCount() {
        let before = item(votes: [VoteRef(photoId: photoA, voterId: viewer)], voteCount: 4)

        let result = PostCardContent.applyingVote(photoB, voterId: viewer, to: before)

        XCTAssertEqual(result.ownVote(voterId: viewer), photoB)
        XCTAssertEqual(result.fitCheckVotes.filter { $0.voterId == viewer }.count, 1)
        XCTAssertEqual(result.voteCount, 4)
    }

    func testApplyingNilRemovesViewersRowAndDropsCount() {
        let before = item(votes: [VoteRef(photoId: photoA, voterId: viewer)], voteCount: 4)

        let result = PostCardContent.applyingVote(nil, voterId: viewer, to: before)

        XCTAssertNil(result.ownVote(voterId: viewer))
        XCTAssertEqual(result.voteCount, 3)
    }

    func testApplyingNilWithNoVoteChangesNothing() {
        let before = item(voteCount: 4)

        let result = PostCardContent.applyingVote(nil, voterId: viewer, to: before)

        XCTAssertEqual(result.voteCount, 4)
        XCTAssertTrue(result.fitCheckVotes.isEmpty)
    }

    func testApplyingVoteKeepsOtherVotersRows() {
        let other = VoteRef(photoId: photoB, voterId: UUID())

        let result = PostCardContent.applyingVote(photoA, voterId: viewer, to: item(votes: [other]))

        XCTAssertTrue(result.fitCheckVotes.contains { $0.voterId == other.voterId && $0.photoId == photoB })
        XCTAssertEqual(result.ownVote(voterId: viewer), photoA)
    }

    func testApplyingVoteLeavesAnUnknownCountUnknown() {
        let result = PostCardContent.applyingVote(photoA, voterId: viewer, to: item(voteCount: nil))

        XCTAssertNil(result.voteCount)
    }

    func testRetractingNeverDropsTheCountBelowZero() {
        let before = item(votes: [VoteRef(photoId: photoA, voterId: viewer)], voteCount: 0)

        let result = PostCardContent.applyingVote(nil, voterId: viewer, to: before)

        XCTAssertEqual(result.voteCount, 0)
    }

    func testApplyingVoteDoesNotMutateTheOriginalItem() {
        let before = item(voteCount: 1)

        _ = PostCardContent.applyingVote(photoA, voterId: viewer, to: before)

        XCTAssertTrue(before.fitCheckVotes.isEmpty)
        XCTAssertEqual(before.voteCount, 1)
    }

    // MARK: Button wording

    func testVoteButtonTitleNamesTheLook() {
        XCTAssertEqual(PostCardContent.voteButtonTitle(position: 2), "Look 2")
    }

    func testVoteButtonAccessibilityLabelSaysVote() {
        XCTAssertEqual(PostCardContent.voteButtonAccessibilityLabel(position: 3), "Vote for Look 3")
    }
}
