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

    func testCreateFooterFitsAccessibilityText() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uiTestSampleData", "--uiTestCreatePhotos",
                                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["tabPlusButton"].waitForExistence(timeout: 15))
        app.buttons["tabPlusButton"].tap()
        let next = app.buttons["createNextButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(next.isEnabled)
        next.tap()
        let back = app.buttons["createBackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isHittable)
        XCTAssertFalse(back.frame.intersects(next.frame), "Create controls should not overlap at large text sizes.")
    }

    func testCreateReviewsEachPhotoAndPostSettingsBeforeUpload() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uiTestSampleData", "--uiTestCreatePhotos"]
        app.launch()
        XCTAssertTrue(app.buttons["tabPlusButton"].waitForExistence(timeout: 15))
        app.buttons["tabPlusButton"].tap()
        let next = app.buttons["createNextButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        let title = app.textFields["createTitleField"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Evening look")
        next.tap()
        let description = app.textFields["createPhotoDescriptionField"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText("First look")
        app.swipeUp()
        let tag = app.buttons["createPhotoTag-Minimal"]
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        tag.tap()
        next.tap()
        XCTAssertTrue(app.staticTexts["Step 3 of 4 · Photo 2 of 2"].waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.otherElements["createPreview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["createUploadButton"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["createPreviewDuration"].exists)
        XCTAssertTrue(app.staticTexts["createPreviewAudience"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["First look"].exists)
        XCTAssertTrue(app.staticTexts["createPreviewPhotoTags-0"].exists)
    }

    func testCreateCanSkipOptionalPhotoDetails() {
        let app = XCUIApplication()
        app.launchArguments += ["--uiTestSampleData", "--uiTestCreatePhotos"]
        app.launch()
        XCTAssertTrue(app.buttons["tabPlusButton"].waitForExistence(timeout: 15))
        app.buttons["tabPlusButton"].tap()
        let next = app.buttons["createNextButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        let skip = app.buttons["createSkipPhotoDetails"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(app.otherElements["createPreview"].waitForExistence(timeout: 5))
        app.buttons["createBackButton"].tap()
        XCTAssertTrue(app.textFields["createTitleField"].waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.textFields["createPhotoDescriptionField"].waitForExistence(timeout: 5))
        app.buttons["createBackButton"].tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        let upload = app.buttons["createUploadButton"]
        XCTAssertTrue(upload.waitForExistence(timeout: 5))
        upload.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: upload)
        XCTAssertEqual(XCTWaiter().wait(for: [dismissed], timeout: 10), .completed)
        XCTAssertTrue(app.buttons["tabPlusButton"].waitForExistence(timeout: 5))
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

    func testProfileAnalyticsOpensWardrobeInsights() throws {
        let app = launchTestApp()

        let accountTab = app.buttons["accountTab"]
        XCTAssertTrue(accountTab.waitForExistence(timeout: 15))
        accountTab.tap()

        let analytics = app.buttons["profile.analytics"]
        XCTAssertTrue(analytics.waitForExistence(timeout: 10), "Analytics should be on the Profile screen")
        analytics.tap()
        let insights = app.buttons["profile.analytics.wardrobeInsights"]
        XCTAssertTrue(insights.waitForExistence(timeout: 5), "Wardrobe insights should be in the Analytics panel")
        insights.tap()

        XCTAssertTrue(app.navigationBars["Wardrobe insights"].waitForExistence(timeout: 5))
        // An empty test wardrobe shows the empty state; otherwise the dimension chips.
        let colorChip = app.buttons["wardrobeInsights.dimension.color"]
        let emptyState = app.staticTexts["No pieces yet"]
        XCTAssertTrue(colorChip.waitForExistence(timeout: 10) || emptyState.exists)
        if colorChip.exists {
            colorChip.tap()
            XCTAssertTrue(colorChip.isSelected, "Tapping a dimension chip should select it")
        }
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
