import XCTest
@testable import CLOV

final class FeedInviteTests: XCTestCase {
    func testShowsOnAThinFeedOnceLoaded() {
        XCTAssertTrue(FeedInvite.shouldShow(postCount: 0, hasLoaded: true))
        XCTAssertTrue(FeedInvite.shouldShow(postCount: FeedInvite.sparseFeedThreshold - 1, hasLoaded: true))
    }

    func testHiddenOnABusyFeedOrBeforeLoading() {
        XCTAssertFalse(FeedInvite.shouldShow(postCount: FeedInvite.sparseFeedThreshold, hasLoaded: true))
        XCTAssertFalse(FeedInvite.shouldShow(postCount: 0, hasLoaded: false))
    }

    func testMessageIncludesTheViewersID() {
        XCTAssertEqual(FeedInvite.message(accountCode: "CLOV-AB12"),
                       "Help me pick my outfit on CLO·V! Add me with my ID: CLOV-AB12")
    }

    func testMessageWithoutAnIDStillInvites() {
        XCTAssertEqual(FeedInvite.message(accountCode: nil), "Help me pick my outfit on CLO·V!")
        XCTAssertEqual(FeedInvite.message(accountCode: "  "), "Help me pick my outfit on CLO·V!")
    }
}
