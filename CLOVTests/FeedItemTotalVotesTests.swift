import XCTest
@testable import CLOV

final class FeedItemTotalVotesTests: XCTestCase {
    private func item(voteCount: Int?, embeddedVotes: Int, createdAt: Date = Date()) -> FeedItemDTO {
        let votes = (0..<embeddedVotes).map { _ in VoteRef(photoId: UUID(), voterId: UUID()) }
        return FeedItemDTO(id: UUID(), creatorId: UUID(), createdAt: createdAt, fitCheckPhotos: [],
                           fitCheckVotes: votes, fitCheckComments: [], voteCount: voteCount)
    }

    func testTotalVotesPrefersVoteCount() {
        XCTAssertEqual(item(voteCount: 12, embeddedVotes: 1).totalVotes, 12)
    }

    func testTotalVotesFallsBackToEmbeddedVotes() {
        XCTAssertEqual(item(voteCount: nil, embeddedVotes: 3).totalVotes, 3)
    }

    func testOwnVoteReadsOnlyViewersRow() {
        let me = UUID(), photo = UUID()
        let mine = VoteRef(photoId: photo, voterId: me)
        let dto = FeedItemDTO(id: UUID(), creatorId: UUID(), createdAt: Date(), fitCheckPhotos: [],
                              fitCheckVotes: [VoteRef(photoId: UUID(), voterId: UUID()), mine],
                              fitCheckComments: [])
        XCTAssertEqual(dto.ownVote(voterId: me), photo)
        XCTAssertNil(dto.ownVote(voterId: UUID()))
    }

    func testFeedRankingVotesSortUsesVoteCountOverEmbed() {
        let popular = item(voteCount: 50, embeddedVotes: 0)
        let embedHeavy = item(voteCount: 2, embeddedVotes: 5)
        let ids = FeedRanking.visibleItems(items: [embedHeavy, popular], searchText: "", occasion: nil,
                                           mode: .forYou, sort: .votes, stylePreferences: [],
                                           signalScores: [:]).map(\.id)
        XCTAssertEqual(ids, [popular.id, embedHeavy.id])
    }

    func testExploreMostVotedUsesVoteCountOverEmbed() {
        let popular = item(voteCount: 50, embeddedVotes: 0)
        let embedHeavy = item(voteCount: 2, embeddedVotes: 5)
        var filter = ExploreFilter()
        filter.sort = .mostVoted
        XCTAssertEqual(filter.apply(to: [embedHeavy, popular]).map(\.id), [popular.id, embedHeavy.id])
    }

    func testShareTextFallsBackWhenCountsUnknown() {
        XCTAssertEqual(VoteShareText.make(from: nil), VoteShareText.fallback)
        XCTAssertEqual(VoteShareText.make(from: .hidden(myVote: nil)), VoteShareText.fallback)
    }

    func testShareTextUsesRevealedSummary() {
        let a = UUID(), b = UUID()
        let summary = VoteSummary(counts: [a: 3, b: 1], total: 4, myVote: a, isRevealed: true)
        XCTAssertEqual(VoteShareText.make(from: summary),
                       "My Fit-Check is at 75% for the leading look (4 votes).")
    }
}
