import XCTest
@testable import CLOV

@MainActor
final class ReelHoldToVoteTests: XCTestCase {
    private let creator = UUID()
    private let viewer = UUID()
    private let photoA = UUID()
    private let photoB = UUID()

    private func makeItem(expiresAt: Date? = Date().addingTimeInterval(3600), votes: [VoteRef] = []) -> FeedItemDTO {
        let id = UUID()
        return FeedItemDTO(
            id: id, creatorId: creator, caption: nil, occasion: nil, audience: nil, votePrompt: nil,
            createdAt: Date(), expiresAt: expiresAt,
            fitCheckPhotos: [
                FitCheckPhoto(id: photoA, fitCheckId: id, imageUrl: "https://example.com/a.jpg", position: 1),
                FitCheckPhoto(id: photoB, fitCheckId: id, imageUrl: "https://example.com/b.jpg", position: 2)
            ],
            fitCheckVotes: votes, fitCheckComments: [], profiles: nil, isPublic: true)
    }

    private struct FakeFailure: Error {}

    /// Fake network: each call suspends until released, then succeeds or throws. Never hits the network.
    @MainActor
    private final class FakeVoteNetwork {
        var castResult: Result<Void, Error> = .success(())
        var retractResult: Result<Void, Error> = .success(())
        var serverSummary: VoteSummary?
        private(set) var summaryCalls = 0
        private(set) var castCalls = 0
        private(set) var retractCalls = 0
        private var castGate: CheckedContinuation<Void, Never>?
        private var retractGate: CheckedContinuation<Void, Never>?
        var holdCast = false
        var holdRetract = false
        // Sticky release flags: a release that arrives before the request task has
        // started waiting must not be lost, or the request would wait forever.
        private var castReleased = false
        private var retractReleased = false

        var service: ReelVoteService {
            ReelVoteService(
                cast: { [self] _, _, _ in
                    castCalls += 1
                    if holdCast && !castReleased { await withCheckedContinuation { castGate = $0 } }
                    try castResult.get()
                },
                retract: { [self] _, _ in
                    retractCalls += 1
                    if holdRetract && !retractReleased { await withCheckedContinuation { retractGate = $0 } }
                    try retractResult.get()
                },
                fetchSummary: { [self] _, _ in
                    summaryCalls += 1
                    guard let serverSummary else { throw FakeFailure() }
                    return serverSummary
                })
        }

        func releaseCast() { castReleased = true; castGate?.resume(); castGate = nil }
        func releaseRetract() { retractReleased = true; retractGate?.resume(); retractGate = nil }
    }

    private func makeModel(votes: [VoteRef] = [], network: FakeVoteNetwork) -> ReelVoteModel {
        ReelVoteModel(item: makeItem(votes: votes), voterId: viewer,
                      initialSummary: VoteSummary.from(votes: votes, voterId: viewer, myVote: nil),
                      service: network.service)
    }

    private var viewerVoteA: [VoteRef] { [VoteRef(photoId: photoA, voterId: viewer)] }

    func testHoldCompletionVotesForPhotoOnScreen() async {
        let network = FakeVoteNetwork()
        let model = makeModel(network: network)
        model.setLook(1)
        XCTAssertTrue(model.voteForCurrentLook {})
        XCTAssertEqual(model.myVote, photoB)
        XCTAssertEqual(model.total, 1)
        XCTAssertEqual(model.percent(for: photoB), 100)
        await model.waitUntilIdle()
        XCTAssertEqual(network.castCalls, 1)
        XCTAssertEqual(model.myVote, photoB)
    }

    func testSecondVoteIsRejectedWhileFirstIsPending() async {
        let network = FakeVoteNetwork()
        network.holdCast = true
        let model = makeModel(network: network)
        XCTAssertTrue(model.voteForCurrentLook {})
        XCTAssertFalse(model.voteForCurrentLook {})
        network.releaseCast()
        await model.waitUntilIdle()
        XCTAssertEqual(network.castCalls, 1)
    }

    func testVoteIsBlockedWhileRetractIsInFlight() async {
        let network = FakeVoteNetwork()
        network.holdRetract = true
        let model = makeModel(votes: viewerVoteA, network: network)
        model.retractVote {}
        XCTAssertNil(model.myVote)
        XCTAssertFalse(model.canVote)
        XCTAssertFalse(model.voteForCurrentLook {})
        network.releaseRetract()
        await model.waitUntilIdle()
        XCTAssertEqual(network.castCalls, 0)
        XCTAssertTrue(model.canVote)
    }

    func testRetractIsBlockedWhileVoteIsInFlight() async {
        let network = FakeVoteNetwork()
        network.holdCast = true
        let model = makeModel(network: network)
        XCTAssertTrue(model.voteForCurrentLook {})
        XCTAssertFalse(model.canRetract)
        model.retractVote {}
        XCTAssertEqual(model.myVote, photoA)
        network.releaseCast()
        await model.waitUntilIdle()
        XCTAssertEqual(network.retractCalls, 0)
    }

    func testRetractFailureRestoresVoteAndCounts() async {
        let network = FakeVoteNetwork()
        network.retractResult = .failure(FakeFailure())
        let model = makeModel(votes: viewerVoteA, network: network)
        model.retractVote {}
        XCTAssertEqual(model.total, 0)
        await model.waitUntilIdle()
        XCTAssertEqual(model.myVote, photoA)
        XCTAssertEqual(model.total, 1)
        XCTAssertEqual(model.counts[photoA], 1)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.isRetracting)
    }

    func testCastFailureRollsBackOptimisticVote() async {
        let network = FakeVoteNetwork()
        network.castResult = .failure(FakeFailure())
        let model = makeModel(network: network)
        XCTAssertTrue(model.voteForCurrentLook {})
        await model.waitUntilIdle()
        XCTAssertNil(model.myVote)
        XCTAssertEqual(model.total, 0)
        XCTAssertEqual(model.counts[photoA] ?? 0, 0)
    }

    func testAlreadyVotedResyncsFromServerWithoutDoubleCount() async {
        let network = FakeVoteNetwork()
        network.castResult = .failure(APIError.alreadyVoted)
        network.serverSummary = VoteSummary(counts: [photoA: 1, photoB: 1], total: 2,
                                            myVote: photoA, isRevealed: true)
        let model = makeModel(network: network)
        XCTAssertTrue(model.voteForCurrentLook {})
        await model.waitUntilIdle()
        XCTAssertEqual(model.total, 2)
        XCTAssertEqual(model.counts[photoA], 1)
        XCTAssertEqual(model.counts[photoB], 1)
        XCTAssertEqual(model.myVote, photoA)
    }

    func testAlreadyVotedWithFailedResyncRestoresPreVoteTally() async {
        let network = FakeVoteNetwork()
        network.castResult = .failure(APIError.alreadyVoted)
        let model = ReelVoteModel(
            item: makeItem(), voterId: viewer, initialSummary: .hidden(myVote: nil),
            service: ReelVoteService(cast: { _, _, _ in throw APIError.alreadyVoted },
                                     retract: { _, _ in },
                                     fetchSummary: { _, _ in throw FakeFailure() }))
        XCTAssertTrue(model.voteForCurrentLook {})
        await model.waitUntilIdle()
        XCTAssertEqual(model.total, 0)
        XCTAssertEqual(model.counts[photoA] ?? 0, 0)
        XCTAssertNotNil(model.myVote)
    }

    func testRefreshSummaryAppliesServerCountsWhenIdle() async {
        let network = FakeVoteNetwork()
        network.serverSummary = VoteSummary(counts: [photoA: 3, photoB: 1], total: 4,
                                            myVote: photoB, isRevealed: true)
        let model = makeModel(network: network)
        await model.loadSummary()
        XCTAssertEqual(model.total, 4)
        XCTAssertEqual(model.counts[photoA], 3)
        XCTAssertEqual(model.myVote, photoB)
    }

    func testRefreshSummaryIsSkippedWhileVoteIsInFlight() async {
        let network = FakeVoteNetwork()
        network.holdCast = true
        network.serverSummary = VoteSummary(counts: [photoB: 9], total: 9, myVote: photoB, isRevealed: true)
        let model = makeModel(network: network)
        XCTAssertTrue(model.voteForCurrentLook {})
        await model.refreshSummary()
        XCTAssertEqual(network.summaryCalls, 0)
        XCTAssertEqual(model.total, 1)
        XCTAssertEqual(model.myVote, photoA)
        network.releaseCast()
        await model.waitUntilIdle()
        XCTAssertEqual(network.summaryCalls, 1)
        XCTAssertEqual(model.total, 9)
    }

    func testOtherVotersRowsAreNeverMyVote() {
        let others = [VoteRef(photoId: photoA, voterId: UUID()), VoteRef(photoId: photoB, voterId: UUID())]
        let model = makeModel(votes: others, network: FakeVoteNetwork())
        XCTAssertNil(model.myVote)
        XCTAssertTrue(model.canVote)
        XCTAssertFalse(model.isResultsRevealed)
    }

    func testTotalPrefersPublicVoteCount() {
        var item = makeItem(votes: viewerVoteA)
        item.voteCount = 7
        XCTAssertEqual(ReelVoteModel(item: item, voterId: viewer).total, 7)
    }

    func testUnrevealedSummaryDoesNotApplyCounts() async {
        let network = FakeVoteNetwork()
        network.serverSummary = .hidden(myVote: nil)
        let model = makeModel(network: network)
        await model.refreshSummary()
        XCTAssertTrue(model.counts.isEmpty)
        XCTAssertEqual(model.total, 0)
        XCTAssertFalse(model.isResultsRevealed)
    }

    func testCreatorAndExpiredPostsCannotVote() {
        XCTAssertFalse(ReelVoteModel(item: makeItem(), voterId: creator).canVote)
        XCTAssertFalse(ReelVoteModel(item: makeItem(expiresAt: Date().addingTimeInterval(-60)), voterId: viewer).canVote)
    }

    func testResultsStayHiddenUntilVotedCreatorOrEnded() {
        XCTAssertFalse(ReelVoteModel(item: makeItem(), voterId: viewer).isResultsRevealed)
        XCTAssertTrue(ReelVoteModel(item: makeItem(), voterId: creator).isResultsRevealed)
        XCTAssertTrue(ReelVoteModel(item: makeItem(expiresAt: Date().addingTimeInterval(-60)), voterId: viewer).isResultsRevealed)
        let voted = ReelVoteModel(item: makeItem(votes: [VoteRef(photoId: photoA, voterId: viewer)]), voterId: viewer,
                                   initialSummary: VoteSummary.from(votes: [VoteRef(photoId: photoA, voterId: viewer)], voterId: viewer, myVote: nil))
        XCTAssertTrue(voted.isResultsRevealed)
        XCTAssertFalse(voted.canVote)
    }

    func testSetLookIgnoresOutOfRangeIndexes() {
        let model = ReelVoteModel(item: makeItem(), voterId: viewer)
        model.setLook(5)
        XCTAssertEqual(model.lookIndex, 0)
        model.setLook(-1)
        XCTAssertEqual(model.lookIndex, 0)
        model.setLook(1)
        XCTAssertEqual(model.lookIndex, 1)
    }

    func testLookIndexWrapsInBothDirections() {
        XCTAssertEqual(SwipeVoteGesture.index(after: 1, count: 2, step: 1), 0)
        XCTAssertEqual(SwipeVoteGesture.index(after: 0, count: 4, step: -1), 3)
        XCTAssertEqual(SwipeVoteGesture.index(after: 0, count: 0, step: 1), 0)
    }

    func testHoldProgressNeedsSystemCompletionToFinish() {
        var hold = HoldProgress.idle.begin().tick(elapsed: HoldProgress.duration * 2)
        XCTAssertEqual(hold.phase, .holding)
        XCTAssertEqual(hold.progress, 1)
        hold = hold.complete()
        XCTAssertEqual(hold.phase, .completed)
        XCTAssertEqual(HoldProgress.idle.begin().tick(elapsed: 0.2).cancel(), .idle)
    }

    func testCommentSendValidation() {
        XCTAssertFalse(CommentThreadSheet.canSend("   "))
        XCTAssertTrue(CommentThreadSheet.canSend("Love it"))
        XCTAssertFalse(CommentThreadSheet.canSend(String(repeating: "a", count: CommentThreadSheet.maxLength + 1)))
    }
}
