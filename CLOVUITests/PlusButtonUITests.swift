import XCTest

final class PlusButtonUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTappingPlusOpensCreateFitCheck() throws {
        let app = XCUIApplication()
        // Real Auth gates the tab bar now — auto-login as a fixed test
        // account (created on first run) instead of scripting the
        // AuthView form. See AppState+UITesting.swift.
        app.launchArguments += ["--uiTestAutoLogin"]
        app.launchEnvironment["UITEST_EMAIL"] = "clov-ui-test@example.com"
        app.launchEnvironment["UITEST_PASSWORD"] = "uiTestPass123"
        app.launch()

        let plusButton = app.buttons["tabPlusButton"]
        XCTAssertTrue(plusButton.waitForExistence(timeout: 15), "Plus button never appeared — tab bar may not have rendered (auto-login/onboarding may have failed, e.g. email confirmation required on the backend).")
        XCTAssertTrue(plusButton.isHittable, "Plus button exists but is not hittable (something is overlapping it).")

        plusButton.tap()

        let createTitle = app.staticTexts["createFitCheckTitle"]
        XCTAssertTrue(createTitle.waitForExistence(timeout: 5), "Tapping the plus button did not open the Create Fit-Check screen.")
    }
}
