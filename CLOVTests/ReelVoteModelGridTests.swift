import XCTest
@testable import CLOV

/// `ReelVoteModel` also drives the detail screen's voting grid, so it must
/// vote for a tapped photo (not just the one on screen), honour a post that
/// isn't live, and take its starting tally from the parent's server summary.
@MainActor
final class ReelVoteModelGridTests: XCTestCase {
    private let creator = UUID()
    private let viewer = UUID()
    private let photoA = UUID()
    private let photoB = UUID()

    private func makeItem(expiresAt: Date? = Date().addingTimeInterval(3600)) -> FeedItemDTO {
        let id = UUID()
        return FeedItemDTO(
            id: id, creatorId: creator, createdAt: Date(), expiresAt: expiresAt,
            fitCheckPhotos: [
                FitCheckPhoto(id: photoA, fitCheckId: id, imageUrl: "https://example.com/a.jpg", position: 1),
                FitCheckPhoto(id: photoB, fitCheckId: id, imageUrl: "https://example.com/b.jpg", position: 2)
            ],
            fitCheckVotes: [], fitCheckComments: [])
    }

    private func service(summary: VoteSummary? = nil, castCount: Counter = Counter()) -> ReelVoteService {
        ReelVoteService(
            cast: { _, _, _ in castCount.value += 1 },
            retract: { _, _ in },
            fetchSummary: { _, _ in
                guard let summary else { throw URLError(.notConnectedToInternet) }
                return summary
            })
    }

    private final class Counter { var value = 0 }

    func testVoteForTappedPhotoIgnoresTheLookOnScreen() async {
        let model = ReelVoteModel(item: makeItem(), voterId: viewer, service: service())
        XCTAssertEqual(model.lookIndex, 0)
        XCTAssertTrue(model.vote(for: photoB) {})
        XCTAssertEqual(model.myVote, photoB)
        await model.waitUntilIdle()
        XCTAssertEqual(model.myVote, photoB)
    }

    func testVoteForUnknownPhotoIsRejected() {
        let model = ReelVoteModel(item: makeItem(), voterId: viewer, service: service())
        XCTAssertFalse(model.vote(for: UUID()) {})
        XCTAssertNil(model.myVote)
    }

    func testNotLivePostCannotVoteAndShowsResults() {
        let model = ReelVoteModel(item: makeItem(), voterId: viewer, isLive: false, service: service())
        XCTAssertFalse(model.canVote)
        XCTAssertFalse(model.canRetract)
        XCTAssertTrue(model.isEnded)
        XCTAssertTrue(model.isResultsRevealed)
        XCTAssertFalse(model.vote(for: photoA) {})
    }

    func testInitialSummarySeedsTheTally() {
        let summary = VoteSummary(counts: [photoA: 3, photoB: 1], total: 4, myVote: photoB, isRevealed: true)
        let model = ReelVoteModel(item: makeItem(), voterId: viewer, initialSummary: summary, service: service())
        XCTAssertEqual(model.total, 4)
        XCTAssertEqual(model.counts[photoA], 3)
        XCTAssertEqual(model.myVote, photoB)
        XCTAssertFalse(model.canVote)
    }

    func testHiddenInitialSummaryLeavesTheTallyEmpty() {
        let model = ReelVoteModel(item: makeItem(), voterId: viewer,
                                  initialSummary: .hidden(myVote: nil), service: service())
        XCTAssertTrue(model.counts.isEmpty)
        XCTAssertEqual(model.total, 0)
        XCTAssertTrue(model.canVote)
    }

    func testAdoptReplacesTheTallyWhenIdle() {
        let model = ReelVoteModel(item: makeItem(), voterId: viewer, service: service())
        model.adopt(VoteSummary(counts: [photoA: 2], total: 2, myVote: photoA, isRevealed: true))
        XCTAssertEqual(model.total, 2)
        XCTAssertEqual(model.myVote, photoA)
    }

    func testAdoptIsIgnoredWhileAVoteIsInFlight() async {
        let model = ReelVoteModel(item: makeItem(), voterId: viewer, service: service())
        XCTAssertTrue(model.vote(for: photoA) {})
        model.adopt(VoteSummary(counts: [photoB: 9], total: 9, myVote: photoB, isRevealed: true))
        XCTAssertEqual(model.myVote, photoA)
        XCTAssertEqual(model.total, 1)
        await model.waitUntilIdle()
    }

    func testAdoptCanClearAVoteTheServerNoLongerHas() {
        let own = FeedItemDTO(id: UUID(), creatorId: creator, createdAt: Date(), fitCheckPhotos: [],
                              fitCheckVotes: [VoteRef(photoId: photoA, voterId: viewer)], fitCheckComments: [])
        let model = ReelVoteModel(item: own, voterId: viewer, service: service())
        XCTAssertEqual(model.myVote, photoA)
        model.adopt(.hidden(myVote: nil))
        XCTAssertNil(model.myVote)
    }
}
