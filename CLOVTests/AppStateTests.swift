import XCTest
@testable import CLOV

@MainActor
final class AppStateTests: XCTestCase {
    func testSignedOutStateHasNoSession() {
        let state = AppState()
        XCTAssertFalse(state.isSignedIn)
        XCTAssertFalse(state.isOnboarded)
        XCTAssertFalse(state.isRecoveringPassword)
        XCTAssertNil(state.email)
    }

    /// Stale tasks and view bodies read `userId` after sign-out; that used to
    /// be a fatalError. It must now return a value without crashing.
    func testUserIdDoesNotCrashWhenSignedOut() {
        let state = AppState()
        _ = state.userId
    }

    func testSignOutIsSafeWhenAlreadySignedOut() async {
        let state = AppState()
        await state.signOut()
        XCTAssertFalse(state.isSignedIn)
        XCTAssertFalse(state.isLoadingProfile)
        XCTAssertFalse(state.isRecoveringPassword)
    }

    func testContentDidChangeBumpsRevision() {
        let state = AppState()
        let before = state.contentRevision
        state.contentDidChange()
        XCTAssertEqual(state.contentRevision, before + 1)
    }
}

final class APIErrorTests: XCTestCase {
    func testAlreadyVotedHasUserFacingMessage() {
        XCTAssertEqual(APIError.alreadyVoted.errorDescription, "You already voted on this Fit-Check.")
    }

    func testMessageErrorPassesTextThrough() {
        XCTAssertEqual(APIError.message("Nope").errorDescription, "Nope")
    }

    func testUnregisterWithoutTokenIsNoOp() async {
        API.currentDeviceToken = nil
        await API.unregisterDeviceToken()
        XCTAssertNil(API.currentDeviceToken)
    }
}
