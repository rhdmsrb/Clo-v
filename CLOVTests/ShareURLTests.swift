import XCTest
@testable import CLOV

final class ShareURLTests: XCTestCase {
    private let id = UUID(uuidString: "0B5E3E4C-6D5A-4F59-9C2B-3D1F4A1E7A10")!
    private let base = "https://clov.example.com"

    func testBuildsHttpsLinkOnConfiguredHost() {
        XCTAssertEqual(ShareURL.make(fitCheckId: id, base: base)?.absoluteString,
                       "https://clov.example.com/vote/0b5e3e4c-6d5a-4f59-9c2b-3d1f4a1e7a10")
    }

    func testRejectsNonHttpsBase() {
        #if !DEBUG
        XCTAssertNil(ShareURL.make(fitCheckId: id, base: "http://clov.example.com"))
        XCTAssertNil(ShareURL.make(fitCheckId: id, base: ""))
        #endif
        XCTAssertNotEqual(ShareURL.make(fitCheckId: id, base: "http://clov.example.com")?.scheme, "http")
    }

    func testParsesCustomSchemeLink() {
        let url = URL(string: "clov://vote/\(id.uuidString.lowercased())")!
        XCTAssertEqual(ShareURL.fitCheckId(from: url, base: nil), id)
    }

    func testParsesUniversalLinkOnlyForShareHost() {
        let good = URL(string: "https://clov.example.com/vote/\(id.uuidString)")!
        let otherHost = URL(string: "https://evil.example.org/vote/\(id.uuidString)")!
        let wrongPath = URL(string: "https://clov.example.com/profile/\(id.uuidString)")!
        XCTAssertEqual(ShareURL.fitCheckId(from: good, base: base), id)
        XCTAssertNil(ShareURL.fitCheckId(from: otherHost, base: base))
        XCTAssertNil(ShareURL.fitCheckId(from: wrongPath, base: base))
        XCTAssertNil(ShareURL.fitCheckId(from: good, base: nil))
    }

    func testRejectsMalformedIdsAndOtherHosts() {
        XCTAssertNil(ShareURL.fitCheckId(from: URL(string: "clov://vote/not-a-uuid")!, base: base))
        XCTAssertNil(ShareURL.fitCheckId(from: URL(string: "clov://auth-callback/\(id.uuidString)")!, base: base))
    }
}
