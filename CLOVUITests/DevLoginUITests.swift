import XCTest

final class DevLoginUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A synthetic identity must never reach a screen that writes to the DB.
    func testSyntheticLoginCannotEnterOnboarding() throws {
        let app = XCUIApplication()
        app.launch()

        let emailField = app.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "AuthView's email field never appeared.")
        emailField.tap()
        emailField.typeText("1")

        let passwordField = app.secureTextFields.firstMatch
        XCTAssertTrue(passwordField.exists, "Password field not found.")
        passwordField.tap()
        passwordField.typeText("1")

        app.buttons["Log in"].tap()

        XCTAssertTrue(app.staticTexts["Use your real account to log in. The old 1 / 1 shortcut cannot save your profile."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["fitqueen99"].exists)
    }
}
