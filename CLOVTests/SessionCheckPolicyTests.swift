import Auth
import XCTest
@testable import CLOV

final class SessionCheckPolicyTests: XCTestCase {
    private func apiError(_ code: ErrorCode, status: Int) -> AuthError {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.test")!, statusCode: status,
            httpVersion: nil, headerFields: nil
        )!
        return .api(message: "x", errorCode: code, underlyingData: Data(), underlyingResponse: response)
    }

    func testKeepsSessionOnNetworkAndCancellationErrors() {
        XCTAssertFalse(SessionCheckPolicy.shouldSignOut(after: URLError(.notConnectedToInternet)))
        XCTAssertFalse(SessionCheckPolicy.shouldSignOut(after: CancellationError()))
    }

    func testKeepsSessionOnServerErrorsAndRateLimits() {
        XCTAssertFalse(SessionCheckPolicy.shouldSignOut(after: apiError(.unexpectedFailure, status: 500)))
        XCTAssertFalse(SessionCheckPolicy.shouldSignOut(after: apiError(.overRequestRateLimit, status: 429)))
        XCTAssertFalse(SessionCheckPolicy.shouldSignOut(after: apiError(.requestTimeout, status: 504)))
    }

    func testKeepsSessionOnUnknownErrors() {
        struct Unknown: Error {}
        XCTAssertFalse(SessionCheckPolicy.shouldSignOut(after: Unknown()))
    }

    func testSignsOutWhenSessionIsDefinitivelyInvalid() {
        XCTAssertTrue(SessionCheckPolicy.shouldSignOut(after: AuthError.sessionMissing))
        XCTAssertTrue(SessionCheckPolicy.shouldSignOut(after: apiError(.refreshTokenNotFound, status: 400)))
        XCTAssertTrue(SessionCheckPolicy.shouldSignOut(after: apiError(.refreshTokenAlreadyUsed, status: 400)))
        XCTAssertTrue(SessionCheckPolicy.shouldSignOut(after: apiError(.sessionNotFound, status: 403)))
        XCTAssertTrue(SessionCheckPolicy.shouldSignOut(after: apiError(.userBanned, status: 403)))
    }

    func testSignsOutOnUnauthorizedStatusWithUnlistedCode() {
        XCTAssertTrue(SessionCheckPolicy.shouldSignOut(after: apiError(.unknown, status: 401)))
    }
}
