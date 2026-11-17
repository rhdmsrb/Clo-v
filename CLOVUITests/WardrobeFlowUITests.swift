import XCTest

final class WardrobeFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWardrobeEditorRequiresPhotoBeforeSaving() throws {
        let app = launchTestApp()

        let accountTab = app.buttons["accountTab"]
        XCTAssertTrue(accountTab.waitForExistence(timeout: 15))
        accountTab.tap()

        let menu = app.buttons["profile.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let wardrobeButton = app.buttons["profileShortcut_Wardrobe"]
        XCTAssertTrue(wardrobeButton.waitForExistence(timeout: 10))
        wardrobeButton.tap()

        let addButton = app.buttons["Add wardrobe item"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.navigationBars["New item"].waitForExistence(timeout: 5))
        let saveButton = app.buttons["Save item"]
        XCTAssertTrue(saveButton.exists)
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["Add a photo first."].waitForExistence(timeout: 2))
    }

    func testCreateFitCheckExposesWardrobeCompositionActions() throws {
        let app = launchTestApp()

        let plusButton = app.buttons["tabPlusButton"]
        XCTAssertTrue(plusButton.waitForExistence(timeout: 15))
        plusButton.tap()

        XCTAssertTrue(app.staticTexts["createFitCheckTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["My Wardrobe"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["2 photos"].exists)
        XCTAssertTrue(app.buttons["4 photos"].exists)
    }

    func testAccountShowsWeeklyStyleReport() throws {
        let app = launchTestApp()

        let accountTab = app.buttons["accountTab"]
        XCTAssertTrue(accountTab.waitForExistence(timeout: 15))
        accountTab.tap()

        let menu = app.buttons["profile.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "Profile menu should be on the Profile screen")
        menu.tap()
        let weeklyReport = app.buttons["yourWeekButton"]
        XCTAssertTrue(weeklyReport.waitForExistence(timeout: 5), "Your week shortcut should be in the profile menu")
        weeklyReport.tap()

        XCTAssertTrue(app.navigationBars["Your week"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Style momentum"].exists)
    }

    func testFeedDoesNotExposeHeaderModes() throws {
        let app = launchTestApp()

        let feedTab = app.buttons["feedTab"]
        XCTAssertTrue(feedTab.waitForExistence(timeout: 15))
        feedTab.tap()

        XCTAssertFalse(app.buttons["watchFeedButton"].exists)
        XCTAssertFalse(app.buttons["feedMode_Following"].exists)
        XCTAssertFalse(app.buttons["feedMode_ForYou"].exists)
    }

    private func launchTestApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uiTestAutoLogin"]
        app.launchEnvironment["UITEST_EMAIL"] = "clov-ui-test@example.com"
        app.launchEnvironment["UITEST_PASSWORD"] = "uiTestPass123"
        app.launch()
        return app
    }
}
