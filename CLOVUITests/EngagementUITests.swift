import XCTest

/// Recent searches, long-press menus and the vote reveal.
final class EngagementUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Points between the pinned filter bar and the floating tab bar on the test device.
    private static let visibleTop: CGFloat = 190
    private static let visibleBottom: CGFloat = 740

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uiTestSampleData", "-appearance.colorScheme", "light"]
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testSearchRemembersRecentsAndCanClearThem() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["searchTab"].waitForExistence(timeout: 15))
        app.buttons["searchTab"].tap()

        // Fresh install: ideas to try, no history yet.
        let suggestion = app.buttons["suggestion_Brunch"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), "Suggestions missing.")
        attach(app, "1-suggestions")
        suggestion.tap()

        // Searching puts the term into the field; clearing the field shows it as a recent.
        let field = app.textFields["search.query"]
        XCTAssertEqual(field.value as? String, "Brunch")
        app.buttons["Clear search"].tap()
        let recent = app.buttons["recent_Brunch"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5), "Search was not remembered.")
        attach(app, "2-recent")

        app.buttons["search.clearRecents"].tap()
        XCTAssertFalse(app.buttons["recent_Brunch"].exists, "Clear did not remove recents.")
        XCTAssertTrue(app.buttons["suggestion_Brunch"].waitForExistence(timeout: 5), "Suggestions should return.")
    }

    func testLongPressOnACardOffersShareReportAndBlock() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Discover"].firstMatch.waitForExistence(timeout: 15))
        let card = app.otherElements.matching(NSPredicate(format: "label ENDSWITH %@", "’s Fit-Check")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "No Fit-Check card on the feed.")
        card.press(forDuration: 1.2)

        XCTAssertTrue(app.buttons["Copy link"].waitForExistence(timeout: 5), "Long-press menu did not open.")
        XCTAssertTrue(app.buttons["Report"].exists, "Report missing from the menu.")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Block '")).firstMatch.exists, "Block missing.")
        attach(app, "3-context-menu")
    }

    func testVotingRevealsTheResult() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Discover"].firstMatch.waitForExistence(timeout: 15))
        // Scroll until a vote tile sits fully between the pinned filters and the
        // tab bar. `firstMatch` alone can pick a tile hidden under the filters.
        var tile: XCUIElement?
        for _ in 0..<6 where tile == nil {
            tile = app.buttons.matching(NSPredicate(format: "label == 'Look 1'")).allElementsBoundByIndex
                .first { $0.isHittable && $0.frame.minY > Self.visibleTop && $0.frame.maxY < Self.visibleBottom }
            if tile == nil { app.swipeUp() }
        }
        guard let tile else { return XCTFail("No vote tile ever came fully into view.") }
        tile.tap()
        let confirm = app.sheets.buttons["Vote for Look 1"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "No vote confirmation.")
        confirm.tap()
        attach(app, "4-reveal-start")

        // Once revealed a tile stops being a button, so look it up by label and value.
        let revealedTile = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Look 1' AND value CONTAINS 'percent of votes'")).firstMatch
        XCTAssertTrue(revealedTile.waitForExistence(timeout: 5), "Result never revealed after voting.")
        attach(app, "5-reveal-after")
        sleep(3)
        attach(app, "6-reveal-settled")
    }
}
