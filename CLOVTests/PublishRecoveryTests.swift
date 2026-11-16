import XCTest
@testable import CLOV

/// What to do with a draft after `publish_fit_check` threw. The response can be
/// lost after the server already made the post live, so deleting blindly would
/// destroy a real post.
final class PublishRecoveryTests: XCTestCase {
    func testLivePostIsTreatedAsPublished() {
        XCTAssertEqual(API.publishRecovery(for: .live), .treatAsPublished)
    }

    func testStillDraftIsKeptForRetry() {
        // Publish is idempotent, so a retry can finish it without re-uploading.
        XCTAssertEqual(API.publishRecovery(for: .draft), .keepForRetry)
    }

    func testMissingRowIsDiscarded() {
        // Nothing on the server to protect; discard just cleans up uploaded files.
        XCTAssertEqual(API.publishRecovery(for: .missing), .discard)
    }

    func testUnknownStateIsKeptNotDeleted() {
        // The status lookup itself failed (e.g. still offline): never delete on a guess.
        XCTAssertEqual(API.publishRecovery(for: .unknown), .keepForRetry)
    }

    func testStatusStringsMapToStates() {
        XCTAssertEqual(PostServerState(status: "live"), .live)
        XCTAssertEqual(PostServerState(status: "draft"), .draft)
        // An ended or any other published status is also a real post.
        XCTAssertEqual(PostServerState(status: "ended"), .live)
    }
}
