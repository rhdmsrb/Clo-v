import XCTest

final class DevLoginUITests: XCTestCase {
    func testLaunchTransitionsToInteractiveFeed() {
        let app = XCUIApplication()
        app.launchArguments += ["--uiTestSampleData", "--uiTestLaunchTransition"]
        app.launch()
        let feed = app.buttons["feedTab"]
        XCTAssertTrue(feed.waitForExistence(timeout: 15))
        let loading = app.descendants(matching: .any)["launch.loading"]
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: loading)
        XCTAssertEqual(XCTWaiter().wait(for: [dismissed], timeout: 5), .completed)
        let search = app.buttons["searchTab"]
        search.tap()
        XCTAssertTrue(app.textFields["search.query"].waitForExistence(timeout: 5))
    }
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A synthetic identity must never reach a screen that writes to the DB.
    /// The old "1" / "1" shortcut is not a valid sign-in: the email has no "@"
    /// and the password is under six characters, so Log in stays disabled and
    /// the app never leaves the auth screen.
    func testSyntheticLoginCannotEnterOnboarding() throws {
        let app = XCUIApplication()
        app.launch()
        signOutIfNeeded(app)

        let emailField = app.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "AuthView's email field never appeared.")
        emailField.tap()
        emailField.typeText("1")

        let passwordField = app.secureTextFields.firstMatch
        XCTAssertTrue(passwordField.exists, "Password field not found.")
        passwordField.tap()
        passwordField.typeText("1")

        let logIn = app.buttons["Log in"]
        XCTAssertTrue(logIn.exists, "Log in button not found.")
        XCTAssertFalse(logIn.isEnabled, "Log in must stay disabled for the synthetic 1 / 1 credentials.")

        XCTAssertFalse(app.textFields["fitqueen99"].exists, "Onboarding must not be reachable with a synthetic login.")
    }

    func testAuthOffersRecoveryAndAccountCreation() throws {
        let app = XCUIApplication()
        app.launch()
        signOutIfNeeded(app)

        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.secureTextFields["auth.password"].exists)
        XCTAssertFalse(app.buttons["auth.submit"].isEnabled)
        app.buttons["auth.forgotPassword"].tap()
        XCTAssertTrue(app.staticTexts["Reset your password"].waitForExistence(timeout: 5))
        app.swipeDown()

        let switchMode = app.buttons["auth.switchMode"]
        if !switchMode.isHittable { app.swipeUp() }
        XCTAssertTrue(switchMode.waitForExistence(timeout: 5))
        switchMode.tap()
        XCTAssertEqual(app.buttons["auth.submit"].label, "Sign up")
        XCTAssertFalse(app.buttons["auth.forgotPassword"].exists)
    }

    /// Other UI tests (e.g. WardrobeFlowUITests) auto-login and the session
    /// persists in the simulator's keychain, so the app can open signed in.
    /// Start from the auth screen regardless of what ran before.
    private func signOutIfNeeded(_ app: XCUIApplication) {
        // Tell the two states apart by something unique to each. Any text field
        // is not enough: the main tabs also contain one (Search's field), which
        // exists once that tab is built in the background after launch.
        let accountTab = app.buttons["accountTab"]
        let logInButton = app.buttons["Log in"]
        let deadline = Date().addingTimeInterval(10)
        while !accountTab.exists, !logInButton.exists, Date() < deadline { usleep(200_000) }
        if logInButton.exists { return }
        XCTAssertTrue(accountTab.exists, "Neither the auth screen nor the main tabs appeared.")
        accountTab.tap()
        let menu = app.buttons["profile.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Profile menu missing on the Account screen.")
        menu.tap()
        let logOut = app.buttons["profile.logout"]
        XCTAssertTrue(logOut.waitForExistence(timeout: 5), "Log out entry missing from the profile menu.")
        logOut.tap()
    }
}
