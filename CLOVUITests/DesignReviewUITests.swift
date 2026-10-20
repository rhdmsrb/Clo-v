import XCTest

/// Not a real regression test — logs in with a throwaway account supplied
/// through TEST_RUNNER_CLOV_TEST_EMAIL / TEST_RUNNER_CLOV_TEST_PASSWORD
/// (the old "1"/"1" shortcut is blocked), completes onboarding if needed,
/// then walks each main tab, attaching a screenshot at every stop (kept
/// regardless of pass/fail) so the redesign can be reviewed from the
/// resulting .xcresult bundle.
final class DesignReviewUITests: XCTestCase {
    private static let emailKey = "CLOV_TEST_EMAIL"
    private static let passwordKey = "CLOV_TEST_PASSWORD"

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testCaptureMainScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        let email = try XCTUnwrap(environment[Self.emailKey], "Set TEST_RUNNER_\(Self.emailKey) to a throwaway account's email.")
        let password = try XCTUnwrap(environment[Self.passwordKey], "Set TEST_RUNNER_\(Self.passwordKey) to that account's password.")

        let app = XCUIApplication()
        app.launch()
        attach(app, name: "01-auth")

        let emailField = app.textFields.firstMatch
        if emailField.waitForExistence(timeout: 10) {
            emailField.tap()
            emailField.typeText(email)
            app.secureTextFields.firstMatch.tap()
            app.secureTextFields.firstMatch.typeText(password)
            app.buttons["Log in"].tap()
        }

        // Either onboarding or the tab bar comes next.
        let nicknameField = app.textFields["fitqueen99"]
        if nicknameField.waitForExistence(timeout: 10) {
            attach(app, name: "02-onboarding")
            nicknameField.tap()
            nicknameField.typeText("designer")
            app.buttons["Streetwear"].tap()
            app.buttons["Let's go"].tap()
        }

        let feedTitle = app.staticTexts["Discover"]
        XCTAssertTrue(feedTitle.firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "03-feed")

        // Keep a pushed route alive while another tab is active.
        let notifications = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Notifications'")).firstMatch
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        notifications.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))

        app.buttons["accountTab"].tap()
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "04-account")

        app.buttons["groupsTab"].tap()
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "05-groups")

        app.buttons["feedTab"].tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5),
                      "Switching tabs discarded the Feed navigation stack")

        app.buttons["feedTab"].tap()
        XCTAssertFalse(app.navigationBars["Notifications"].waitForExistence(timeout: 2),
                       "Tapping the selected tab did not return it to its root")

        app.buttons["tabPlusButton"].tap()
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "06-create")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
