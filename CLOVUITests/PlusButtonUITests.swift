import XCTest

final class PlusButtonUITests: XCTestCase {
    func testCropControlsCanZoomResetAndSave() {
        let app = XCUIApplication()
        app.launchArguments += ["--uiTestSampleData", "--uiTestCreatePhotos"]
        app.launch()
        let create = app.buttons["tabPlusButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let crop = app.buttons["Crop Photo 1"]
        XCTAssertTrue(crop.waitForExistence(timeout: 10))
        crop.tap()
        let zoom = app.sliders["Crop zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        zoom.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertNotEqual(zoom.value as? String, "100 percent")
        app.buttons["Reset"].tap()
        XCTAssertEqual(zoom.value as? String, "100 percent")
        zoom.adjust(toNormalizedSliderPosition: 0.5)
        let selectedZoom = zoom.value as? String
        app.buttons["Done"].tap()
        XCTAssertTrue(crop.waitForExistence(timeout: 5))
        crop.tap()
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        XCTAssertEqual(zoom.value as? String, selectedZoom)
        app.buttons["Cancel"].tap()
    }
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

    func testTabBarShowsVoteAndWeatherAndGroupsMovedToProfile() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uiTestAutoLogin"]
        app.launchEnvironment["UITEST_EMAIL"] = "clov-ui-test@example.com"
        app.launchEnvironment["UITEST_PASSWORD"] = "uiTestPass123"
        app.launch()

        XCTAssertTrue(app.buttons["voteTab"].waitForExistence(timeout: 15), "Vote tab never appeared.")
        XCTAssertTrue(app.buttons["weatherTab"].exists, "Weather tab missing.")
        for gone in ["groupsTab", "searchTab", "activityTab"] {
            XCTAssertFalse(app.buttons[gone].exists, "\(gone) should no longer be a tab.")
        }
        app.openGroups()
        let groupsRoot = app.descendants(matching: .any)["groups.root"]
        XCTAssertTrue(groupsRoot.waitForExistence(timeout: 5), "Groups did not open from the Profile menu.")
    }
}
