import XCTest

/// Settings gathers account, preferences, privacy and session controls.
final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSettingsShowsEverySectionAndOpensSubscreens() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uiTestSampleData"]
        app.launch()
        XCTAssertTrue(app.buttons["accountTab"].waitForExistence(timeout: 15))
        app.buttons["accountTab"].tap()

        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        attach(app, "1-top")

        XCTAssertTrue(app.buttons["settingsEditProfile"].exists, "Edit profile row missing.")
        XCTAssertTrue(app.buttons["settingsAppearance"].exists, "Appearance row missing.")
        XCTAssertTrue(app.buttons["settingsPrivacy"].exists, "Privacy row missing.")

        // Scroll to the end so the last rows clear the floating tab bar.
        app.swipeUp()
        app.swipeUp()
        let logOut = app.buttons["settingsLogOut"]
        XCTAssertTrue(logOut.isHittable, "Log out row not reachable.")
        XCTAssertTrue(app.buttons["settingsDeleteAccount"].exists, "Delete account row missing.")
        attach(app, "2-bottom")

        // Delete asks for confirmation instead of acting immediately.
        app.buttons["settingsDeleteAccount"].tap()
        XCTAssertTrue(app.alerts["Delete your account?"].waitForExistence(timeout: 5))
        app.alerts["Delete your account?"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].exists)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
