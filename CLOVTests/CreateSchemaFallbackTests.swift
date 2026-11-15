import XCTest
import Supabase
@testable import CLOV

final class CreateSchemaFallbackTests: XCTestCase {
    private func error(code: String?, message: String) -> PostgrestError {
        PostgrestError(details: nil, hint: nil, code: code, message: message)
    }

    func testMissingFunctionAndColumnCodesAreDetected() {
        for code in ["PGRST202", "PGRST204", "42883", "42703"] {
            XCTAssertTrue(API.isMissingColumnError(error(code: code, message: "x")), code)
        }
    }

    func testMessageTextWithoutCodeIsNotDetected() {
        XCTAssertFalse(API.isMissingColumnError(error(code: nil, message: "Could not find the 'tags' column of 'fit_check_photos' in the schema cache")))
        XCTAssertFalse(API.isMissingColumnError(error(code: nil, message: "column fit_checks.tags does not exist")))
    }

    func testRelationshipSchemaCacheErrorIsNotDetected() {
        let message = "Could not find a relationship between 'fit_checks' and 'profiles' in the schema cache"
        XCTAssertFalse(API.isMissingColumnError(error(code: "PGRST200", message: message)))
    }

    func testUnrelatedErrorsAreNotTreatedAsMissingSchema() {
        XCTAssertFalse(API.isMissingColumnError(error(code: "42501", message: "permission denied")))
        XCTAssertFalse(API.isMissingColumnError(error(code: "22023", message: "Draft request conflicts with an existing post")))
        XCTAssertFalse(API.isMissingColumnError(URLError(.notConnectedToInternet)))
        XCTAssertFalse(API.isMissingColumnError(URLError(.timedOut)))
    }
}
