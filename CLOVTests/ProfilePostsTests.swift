import XCTest
@testable import CLOV

final class ProfilePostsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private var expiredCheck: (Date?) -> Bool { { [now] in ($0 ?? .distantFuture) <= now } }

    private func post(_ status: String, expires: Date? = nil, id: UUID = UUID()) -> MyFitCheck {
        MyFitCheck(id: id, caption: nil, status: status, expiresAt: expires, thumbnailURL: nil)
    }

    func testLiveExcludesExpiredAndArchived() {
        let live = post("live", expires: now.addingTimeInterval(60))
        let expired = post("live", expires: now.addingTimeInterval(-60))
        let archived = post("archived")
        let result = ProfilePosts.live([live, expired, archived], isExpired: expiredCheck)
        XCTAssertEqual(result.map(\.id), [live.id])
    }

    func testEndedIncludesArchivedAndExpiredLive() {
        let live = post("live", expires: now.addingTimeInterval(60))
        let expired = post("live", expires: now.addingTimeInterval(-60))
        let archived = post("archived")
        let result = ProfilePosts.ended([live, expired, archived], isExpired: expiredCheck)
        XCTAssertEqual(Set(result.map(\.id)), [expired.id, archived.id])
    }

    func testPostsForSegmentPicksMatchingList() {
        let a = post("live"), b = post("archived"), c = post("saved")
        XCTAssertEqual(ProfilePosts.posts(for: .live, live: [a], ended: [b], saved: [c]).map(\.id), [a.id])
        XCTAssertEqual(ProfilePosts.posts(for: .ended, live: [a], ended: [b], saved: [c]).map(\.id), [b.id])
        XCTAssertEqual(ProfilePosts.posts(for: .saved, live: [a], ended: [b], saved: [c]).map(\.id), [c.id])
    }

    func testDeduplicatedKeepsFirstAndOrder() {
        let id = UUID(), other = UUID()
        let first = MyFitCheck(id: id, caption: "first", status: "saved", thumbnailURL: nil)
        let dupe = MyFitCheck(id: id, caption: "dupe", status: "saved", thumbnailURL: nil)
        let result = ProfilePosts.deduplicated([first, post("saved", id: other), dupe])
        XCTAssertEqual(result.map(\.id), [id, other])
        XCTAssertEqual(result.first?.caption, "first")
    }

    func testRatiosDoNotCrashOnDuplicateIDs() {
        let id = UUID()
        let ratios = ProfilePosts.ratios(for: [post("saved", id: id), post("saved", id: id)])
        XCTAssertEqual(ratios.count, 1)
        XCTAssertEqual(ratios[id], ProfilePosts.tileRatios[0])
    }

    func testSavedErrorClassification() {
        XCTAssertEqual(SavedLoadState.classify(URLError(.notConnectedToInternet)), .failed)
        XCTAssertEqual(SavedLoadState.classify(NSError(domain: "x", code: 1)), .unavailable)
    }

    func testEmptyTextForSavedStates() {
        XCTAssertEqual(ProfilePosts.emptyText(for: .saved, saved: .unavailable), "Saved posts aren't available right now.")
        XCTAssertEqual(ProfilePosts.emptyText(for: .saved, saved: .loaded), "Posts you save will show up here.")
    }
}
