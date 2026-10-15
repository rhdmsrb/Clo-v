import XCTest

/// Verifies a `clov://vote/<id>` share link actually opens this app and
/// respects the voting timer — routes through Safari (like tapping a
/// real link would) rather than `simctl openurl` directly, so it also
/// exercises the system's "Open in CLO-V?" confirmation the same way a
/// person would encounter it.
final class DeepLinkUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExpiredFitCheckLinkShowsVotingEnded() throws {
        // Sign in first so MainTabView (which owns the deep-link
        // fullScreenCover) is actually mounted when the link arrives.
        let clov = XCUIApplication()
        clov.launch()
        let emailField = clov.textFields.firstMatch
        if emailField.waitForExistence(timeout: 10) {
            emailField.tap()
            emailField.typeText("1")
            clov.secureTextFields.firstMatch.tap()
            clov.secureTextFields.firstMatch.typeText("1")
            clov.buttons["Log in"].tap()
            _ = clov.staticTexts["Feed"].waitForExistence(timeout: 10)
        }
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
        addressField.typeText("clov://vote/1a5461a2-3d6f-454e-9de5-1b70fd3a8db1\n")

        let openButton = safari.buttons["Open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 8), "System 'Open in CLO-V?' confirmation never appeared.")
        openButton.tap()

        XCTAssertTrue(clov.wait(for: .runningForeground, timeout: 8), "CLO-V never came to the foreground after the deep link.")

        let endedText = clov.staticTexts["Voting has ended"]
        XCTAssertTrue(endedText.waitForExistence(timeout: 8), "Deep-linking to an expired Fit-Check did not show the 'Voting has ended' placeholder.")

        let attachment = XCTAttachment(screenshot: clov.screenshot())
        attachment.name = "expired-deeplink"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
