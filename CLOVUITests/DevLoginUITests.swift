import XCTest

final class DevLoginUITests: XCTestCase {
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

    /// Other UI tests (e.g. WardrobeFlowUITests) auto-login and the session
    /// persists in the simulator's keychain, so the app can open signed in.
    /// Start from the auth screen regardless of what ran before.
    private func signOutIfNeeded(_ app: XCUIApplication) {
        if app.textFields.firstMatch.waitForExistence(timeout: 8) { return }
        let accountTab = app.buttons["accountTab"]
        XCTAssertTrue(accountTab.waitForExistence(timeout: 5), "Neither the auth screen nor the main tabs appeared.")
        accountTab.tap()
        let logOut = app.buttons["Log out"]
        for _ in 0..<8 where !logOut.isHittable { app.swipeUp() }
        XCTAssertTrue(logOut.isHittable, "Log out button not reachable on the Account screen.")
        logOut.tap()
    }
}
