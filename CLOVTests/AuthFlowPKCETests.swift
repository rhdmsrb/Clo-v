import XCTest
@testable import CLOV

final class AuthFlowPKCETests: XCTestCase {
    func testSessionFromRejectsImplicitGrantFragment() async {
        let crafted = URL(string: "clov://auth-callback#access_token=evil&refresh_token=evil&token_type=bearer")!
        // The simulator may already hold a signed-in session; compare, don't assume nil.
        let before = try? await SupabaseManager.client.auth.session.accessToken
        do {
            _ = try await SupabaseManager.client.auth.session(from: crafted)
            XCTFail("An implicit-grant link must not sign the user in")
        } catch {
            // Expected: PKCE mode only accepts links carrying a `code`.
        }
        let after = try? await SupabaseManager.client.auth.session.accessToken
        XCTAssertEqual(before, after, "A rejected crafted link must not change the session")
        XCTAssertNotEqual(after, "evil")
    }
}
