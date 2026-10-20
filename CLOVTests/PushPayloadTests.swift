import XCTest
@testable import CLOV

final class PushPayloadTests: XCTestCase {
    private let fitCheckId = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

    func testParsesFitCheckIdAndType() {
        let payload = PushPayload(userInfo: ["fitCheckId": fitCheckId.uuidString, "type": "vote"])

        XCTAssertEqual(payload?.fitCheckId, fitCheckId)
        XCTAssertEqual(payload?.type, "vote")
    }

    func testTypeIsOptional() {
        let payload = PushPayload(userInfo: ["fitCheckId": fitCheckId.uuidString])

        XCTAssertEqual(payload?.fitCheckId, fitCheckId)
        XCTAssertNil(payload?.type)
    }

    func testRejectsMissingFitCheckId() {
        XCTAssertNil(PushPayload(userInfo: ["type": "vote"]))
        XCTAssertNil(PushPayload(userInfo: [:]))
    }

    func testRejectsMalformedFitCheckId() {
        XCTAssertNil(PushPayload(userInfo: ["fitCheckId": "not-a-uuid"]))
        XCTAssertNil(PushPayload(userInfo: ["fitCheckId": 42]))
    }

    func testIgnoresUnrelatedKeysAndNonStringType() {
        let payload = PushPayload(userInfo: [
            "aps": ["alert": "hi"],
            "fitCheckId": fitCheckId.uuidString,
            "type": 7,
        ])

        XCTAssertEqual(payload?.fitCheckId, fitCheckId)
        XCTAssertNil(payload?.type)
    }
}
