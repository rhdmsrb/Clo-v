import XCTest
@testable import CLOV

final class SharedComponentsLogicTests: XCTestCase {
    // MARK: HoldProgress
    func testHoldCompletesOnlyAfterBegin() {
        XCTAssertEqual(HoldProgress.idle.complete(), .idle)
        let done = HoldProgress.idle.begin().tick(elapsed: 0.6).complete()
        XCTAssertEqual(done.phase, .completed)
        XCTAssertEqual(done.progress, 1)
    }

    func testHoldTickIsClampedAndMonotonic() {
        let a = HoldProgress.idle.begin().tick(elapsed: 0.3)
        XCTAssertEqual(a.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(a.tick(elapsed: 0.1).progress, a.progress)
        XCTAssertEqual(a.tick(elapsed: 5).progress, 1)
        XCTAssertEqual(a.tick(elapsed: 5).phase, .holding)
    }

    func testEarlyLiftCancelsToIdle() {
        XCTAssertEqual(HoldProgress.idle.begin().tick(elapsed: 0.4).cancel(), .idle)
    }

    func testCancelDoesNotUndoCompletion() {
        let done = HoldProgress.idle.begin().complete()
        XCTAssertEqual(done.cancel(), done)
        XCTAssertEqual(done.begin(), done)
        XCTAssertEqual(done.reset(), .idle)
    }

    func testMilestonesCrossedOnce() {
        let start = HoldProgress.idle.begin()
        let mid = start.tick(elapsed: 0.25)
        XCTAssertEqual(mid.crossedMilestones(since: start), 1)
        XCTAssertEqual(mid.tick(elapsed: 0.26).crossedMilestones(since: mid), 0)
        XCTAssertEqual(start.tick(elapsed: 0.6).crossedMilestones(since: start), 2)
    }

    // MARK: Carousel
    func testAdvanceWrapsAround() {
        var logic = CarouselAutoAdvance(pageCount: 3)
        logic = logic.advanced().advanced()
        XCTAssertEqual(logic.index, 2)
        XCTAssertEqual(logic.advanced().index, 0)
    }

    func testUserInteractionStopsPermanently() {
        let stopped = CarouselAutoAdvance(pageCount: 3).userInteracted()
        XCTAssertEqual(stopped.advanced().index, 0)
        XCTAssertTrue(stopped.moved(to: 2).isStopped)
        XCTAssertFalse(stopped.shouldRun(enabled: true, reduceMotion: false, isOnScreen: true))
    }

    func testShouldRunRules() {
        let logic = CarouselAutoAdvance(pageCount: 3)
        XCTAssertTrue(logic.shouldRun(enabled: true, reduceMotion: false, isOnScreen: true))
        XCTAssertFalse(logic.shouldRun(enabled: false, reduceMotion: false, isOnScreen: true))
        XCTAssertFalse(logic.shouldRun(enabled: true, reduceMotion: true, isOnScreen: true))
        XCTAssertFalse(logic.shouldRun(enabled: true, reduceMotion: false, isOnScreen: false))
        XCTAssertFalse(CarouselAutoAdvance(pageCount: 1).shouldRun(enabled: true, reduceMotion: false, isOnScreen: true))
    }

    /// VoiceOver and Switch Control users move through photos on their own;
    /// pages changing under their focus is disorienting (and WCAG 2.2.2).
    func testShouldNotRunWhileAssistiveTechIsActive() {
        let logic = CarouselAutoAdvance(pageCount: 3)
        XCTAssertFalse(logic.shouldRun(enabled: true, reduceMotion: false, isOnScreen: true, assistiveTechActive: true))
        XCTAssertTrue(logic.shouldRun(enabled: true, reduceMotion: false, isOnScreen: true, assistiveTechActive: false))
    }

    func testIndexClampedAndIntervalIsThreeSeconds() {
        XCTAssertEqual(CarouselAutoAdvance(pageCount: 2, index: 9).index, 1)
        XCTAssertEqual(CarouselAutoAdvance(pageCount: 0).advanced().index, 0)
        XCTAssertEqual(CarouselAutoAdvance.interval, 3)
    }

    // MARK: Masonry
    func testMasonryPlacesInShortestColumn() {
        // Tall (0.5 -> h2), then short items fill the other column until it catches up.
        let columns = MasonryLayout.assign(aspectRatios: [0.5, 1, 1, 1])
        XCTAssertEqual(columns, [[0, 3], [1, 2]])
    }

    func testMasonryTieGoesLeftAndHandlesEmpty() {
        XCTAssertEqual(MasonryLayout.assign(aspectRatios: [1, 1]), [[0], [1]])
        XCTAssertEqual(MasonryLayout.assign(aspectRatios: []), [[], []])
        XCTAssertEqual(MasonryLayout.assign(aspectRatios: [1], columnCount: 0), [[0]])
    }

    func testMasonryBadRatiosFallBack() {
        XCTAssertEqual(MasonryLayout.clampedRatio(0), 1)
        XCTAssertEqual(MasonryLayout.clampedRatio(.nan), 1)
        XCTAssertEqual(MasonryLayout.clampedRatio(10), 2)
        XCTAssertEqual(MasonryLayout.clampedRatio(0.1), 0.5)
    }

    // MARK: OptimisticToggle / BlurReveal
    func testOptimisticToggleFlipsAndRollsBack() throws {
        let start = OptimisticToggle(isOn: false, count: 4)
        let flipped = try XCTUnwrap(start.toggled())
        XCTAssertTrue(flipped.isOn)
        XCTAssertEqual(flipped.count, 5)
        XCTAssertNil(flipped.toggled())
        let back = flipped.rolledBack()
        XCTAssertFalse(back.isOn)
        XCTAssertEqual(back.count, 4)
        XCTAssertFalse(back.isPending)
    }

    func testSyncIgnoredWhilePending() throws {
        let flipped = try XCTUnwrap(OptimisticToggle(isOn: false).toggled())
        XCTAssertEqual(flipped.synced(isOn: false, count: nil), flipped)
        XCTAssertFalse(flipped.succeeded().synced(isOn: false, count: nil).isOn)
    }

    func testBlurRevealRule() {
        XCTAssertFalse(BlurReveal.isRevealed(hasVoted: false, isCreator: false, ended: false))
        XCTAssertTrue(BlurReveal.isRevealed(hasVoted: true, isCreator: false, ended: false))
        XCTAssertTrue(BlurReveal.isRevealed(hasVoted: false, isCreator: true, ended: false))
        XCTAssertTrue(BlurReveal.isRevealed(hasVoted: false, isCreator: false, ended: true))
    }
}
