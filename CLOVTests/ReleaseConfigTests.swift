import XCTest
@testable import CLOV

/// Guards for App Store / auth configuration that is easy to break silently.
final class ReleaseConfigTests: XCTestCase {
    private func privacyManifest() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                                "PrivacyInfo.xcprivacy is not bundled")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testPrivacyManifestDeclaresUserDefaultsReason() throws {
        let apis = try XCTUnwrap(privacyManifest()["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaults = apis.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" }
        let reasons = try XCTUnwrap(userDefaults?["NSPrivacyAccessedAPITypeReasons"] as? [String])
        XCTAssertTrue(reasons.contains("CA92.1"))
    }

    func testPrivacyManifestDeclaresDataTheAppCollects() throws {
        let collected = try XCTUnwrap(privacyManifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let declared = Set(collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        for type in ["EmailAddress", "Name", "PhotosorVideos", "CoarseLocation", "UserID", "DeviceID", "OtherUserContent", "ProductInteraction"] {
            XCTAssertTrue(declared.contains("NSPrivacyCollectedDataType\(type)"), "missing \(type)")
        }
    }

    func testPrivacyManifestDoesNotClaimTracking() throws {
        XCTAssertEqual(try privacyManifest()["NSPrivacyTracking"] as? Bool, false)
    }

    func testAuthCallbackSchemeIsRegisteredInInfoPlist() throws {
        let types = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertEqual(AppConfig.authCallbackURL.scheme, "clov")
        XCTAssertEqual(AppConfig.authCallbackURL.host, "auth-callback")
        XCTAssertTrue(schemes.contains(AppConfig.authCallbackURL.scheme ?? ""))
    }
}
