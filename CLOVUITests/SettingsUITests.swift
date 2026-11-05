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

    func testBlockedPeopleCanBeUnblocked() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uiTestSampleData"]
        app.launch()
        XCTAssertTrue(app.buttons["accountTab"].waitForExistence(timeout: 15))
        app.buttons["accountTab"].tap()
        app.buttons["settingsButton"].tap()

        let blocked = app.buttons["settingsBlocked"]
        for _ in 0..<4 where !blocked.isHittable { app.swipeUp() }
        blocked.tap()
        XCTAssertTrue(app.navigationBars["Blocked people"].waitForExistence(timeout: 5))

        let unblock = app.buttons["unblock_trend.chaser"]
        XCTAssertTrue(unblock.waitForExistence(timeout: 5), "Sample blocked person missing.")
        XCTAssertTrue(app.buttons["unblock_fit.critic"].exists)
        attach(app, "3-blocked")

        unblock.tap()
        // Unblocking asks first, then removes just that person.
        let confirm = app.sheets.buttons["Unblock trend.chaser"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "No confirmation before unblocking.")
        confirm.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: unblock)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["unblock_fit.critic"].exists, "Unblocking removed the wrong person.")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
