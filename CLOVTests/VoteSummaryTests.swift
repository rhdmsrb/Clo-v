import XCTest
import Supabase
@testable import CLOV

final class VoteSummaryTests: XCTestCase {
    private let photoA = UUID()
    private let photoB = UUID()

    private func decodeFeed(extra: String) throws -> FeedItemDTO {
        let json = """
        {"id":"\(UUID())","creator_id":"\(UUID())","created_at":"2026-01-01T00:00:00Z",
         "fit_check_photos":[],"fit_check_comments":[]\(extra)}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FeedItemDTO.self, from: Data(json.utf8))
    }

    func testFeedWithoutVoteEmbedDecodesAndFeedQueriesNeverRequestIt() throws {
        XCTAssertTrue(try decodeFeed(extra: "").fitCheckVotes.isEmpty)
        XCTAssertFalse(API.feedColumns.contains("fit_check_votes"))
    }

    func testFeedItemDecodesVoteCountWhenPresent() throws {
        XCTAssertEqual(try decodeFeed(extra: ",\"vote_count\":7").voteCount, 7)
    }

    func testFeedItemDecodesWithoutVoteCount() throws {
        XCTAssertNil(try decodeFeed(extra: "").voteCount)
    }

    func testFromSumsCountsAndTotal() {
        let tally = [LivePhotoTally(photoId: photoA, voteCount: 3, isMine: false),
                     LivePhotoTally(photoId: photoB, voteCount: 2, isMine: false)]
        let summary = VoteSummary.from(tally: tally, myVote: nil)
        XCTAssertEqual(summary.counts, [photoA: 3, photoB: 2])
        XCTAssertEqual(summary.total, 5)
        XCTAssertTrue(summary.isRevealed)
    }

    func testFromTakesMyVoteFromIsMineRow() {
        let tally = [LivePhotoTally(photoId: photoA, voteCount: 1, isMine: false),
                     LivePhotoTally(photoId: photoB, voteCount: 1, isMine: true)]
        XCTAssertEqual(VoteSummary.from(tally: tally, myVote: nil).myVote, photoB)
    }

    func testFromPrefersExplicitMyVote() {
        let tally = [LivePhotoTally(photoId: photoB, voteCount: 1, isMine: true)]
        XCTAssertEqual(VoteSummary.from(tally: tally, myVote: photoA).myVote, photoA)
    }

    func testHiddenHasNoCounts() {
        let summary = VoteSummary.hidden(myVote: nil)
        XCTAssertTrue(summary.counts.isEmpty)
        XCTAssertEqual(summary.total, 0)
        XCTAssertFalse(summary.isRevealed)
    }

    func testPlanEndedIsClosed() {
        XCTAssertEqual(VoteSummaryPlan.decide(isEnded: true, isCreator: false, hasVoted: false), .closed)
    }

    func testPlanCreatorLiveIsLive() {
        XCTAssertEqual(VoteSummaryPlan.decide(isEnded: false, isCreator: true, hasVoted: false), .live)
    }

    func testPlanVoterLiveIsLive() {
        XCTAssertEqual(VoteSummaryPlan.decide(isEnded: false, isCreator: false, hasVoted: true), .live)
    }

    func testPlanStrangerLiveIsHidden() {
        XCTAssertEqual(VoteSummaryPlan.decide(isEnded: false, isCreator: false, hasVoted: false), .hidden)
    }

    func testLegacyBuilderCountsRowsAndFindsMyVote() {
        let me = UUID()
        let votes = [VoteRef(photoId: photoA, voterId: me), VoteRef(photoId: photoA, voterId: UUID())]
        let summary = VoteSummary.from(votes: votes, voterId: me, myVote: nil)
        XCTAssertEqual(summary.counts, [photoA: 2])
        XCTAssertEqual(summary.myVote, photoA)
    }
}

/// The device clock only guesses that a post has ended; the server decides. When the
/// closed-results call comes back empty, that guess may have been wrong.
final class ClosedTallyOutcomeTests: XCTestCase {
    private let tally = [LivePhotoTally(photoId: UUID(), voteCount: 3, isMine: false)]

    func testNonEmptyClosedResultsAreRevealed() {
        XCTAssertEqual(API.closedTallyOutcome(closed: tally, isCreator: false, hasVoted: false), .revealed)
    }

    func testEmptyResultsForAVoterFallBackToTheLiveTally() {
        XCTAssertEqual(API.closedTallyOutcome(closed: [], isCreator: false, hasVoted: true), .useLiveTally)
    }

    func testEmptyResultsForTheCreatorFallBackToTheLiveTally() {
        XCTAssertEqual(API.closedTallyOutcome(closed: [], isCreator: true, hasVoted: false), .useLiveTally)
    }

    /// Without a vote there is nothing to prove the post has really ended, so never show "0 votes".
    func testEmptyResultsForAnUndecidedViewerStayHidden() {
        XCTAssertEqual(API.closedTallyOutcome(closed: [], isCreator: false, hasVoted: false), .stayHidden)
    }
}
