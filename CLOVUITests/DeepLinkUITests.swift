import XCTest

/// Verifies a `clov://vote/<id>` share link actually opens this app and
/// respects the voting timer — routes through Safari (like tapping a
/// real link would) rather than `simctl openurl` directly, so it also
/// exercises the system's "Open in CLO-V?" confirmation the same way a
/// person would encounter it.
final class DeepLinkUITests: XCTestCase {
    private static let sampleDataArgument = "--uiTestSampleData"
    /// SampleData fixture 3 ("Brunch outfit"), posted by someone else and
    /// already expired: SampleData.uuid(1_003).
    private static let expiredSampleFitCheckId = "00000000-0000-4000-8000-000000001003"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExpiredFitCheckLinkShowsVotingEnded() throws {
        // Offline sample mode (DEBUG): a fake signed-in, onboarded session with
        // canned data and no network, so MainTabView (which owns the deep-link
        // fullScreenCover) is mounted when the link arrives.
        let clov = XCUIApplication()
        clov.launchArguments.append(Self.sampleDataArgument)
        clov.launch()
        XCTAssertTrue(clov.buttons["feedTab"].waitForExistence(timeout: 15), "Sample session never reached the main tabs.")
        XCUIDevice.shared.press(.home) // send to background without terminating

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        let urlField = safari.textFields["Address"]
        if !urlField.waitForExistence(timeout: 5) {
            safari.textFields["TabBarItemTitle"].firstMatch.tap()
        }
        let addressField = safari.textFields["Address"]
        XCTAssertTrue(addressField.waitForExistence(timeout: 5))
        addressField.tap()
        addressField.typeText("clov://vote/\(Self.expiredSampleFitCheckId)\n")

        let openButton = safari.buttons["Open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 8), "System 'Open in CLO-V?' confirmation never appeared.")
        openButton.tap()

        XCTAssertTrue(clov.wait(for: .runningForeground, timeout: 8), "CLO-V never came to the foreground after the deep link.")

        // VotingEndedView combines its texts into one accessibility element,
        // so match on the label rather than an exact static text.
        let endedText = clov.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Voting has ended")).firstMatch
        XCTAssertTrue(endedText.waitForExistence(timeout: 8), "Deep-linking to an expired Fit-Check did not show the 'Voting has ended' placeholder.")

        let attachment = XCTAttachment(screenshot: clov.screenshot())
        attachment.name = "expired-deeplink"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
