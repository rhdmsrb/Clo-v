import XCTest

/// The palette picker applies live: choosing a palette keeps the user on the
/// Appearance screen (no rebuild or pop) and the choice survives a relaunch.
final class AppearanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uiTestSampleData"]
        app.launch()
        return app
    }

    private func openAppearance(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["accountTab"].waitForExistence(timeout: 15))
        app.buttons["accountTab"].tap()
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let appearance = app.buttons["settingsAppearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5), "Settings never showed the Appearance row.")
        appearance.tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testSelectingPaletteStaysOnScreenAndPersists() throws {
        let app = launch()
        openAppearance(app)
        app.buttons["palette_rose"].tap()
        XCTAssertTrue(app.buttons["palette_rose"].isSelected)
        attach(app, "1-rose")

        app.buttons["palette_forest"].tap()
        XCTAssertTrue(app.navigationBars["Appearance"].exists, "Changing palette must not pop the screen.")
        XCTAssertTrue(app.buttons["palette_forest"].isSelected)
        attach(app, "2-forest")

        app.terminate()
        let relaunched = launch()
        openAppearance(relaunched)
        XCTAssertTrue(relaunched.buttons["palette_forest"].isSelected, "Palette choice did not persist.")
    }
}
