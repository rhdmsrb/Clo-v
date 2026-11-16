import XCTest

/// Recent searches, long-press menus and the vote reveal.
final class EngagementUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

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

        // Focusing the empty field shows ideas to try (no history yet).
        let field = app.textFields["search.query"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Search field missing.")
        field.tap()
        let suggestion = app.buttons["suggestion_Brunch"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10), "Suggestions missing.")
        attach(app, "1-suggestions")
        suggestion.tap()

        // Searching puts the term into the field; clearing the field shows it as a recent.
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

    /// The redesigned vote screen hides the total until the viewer votes: holding
    /// the centre photo casts the vote, shows Undo, and reveals the count.
    func testVotingRevealsTheResult() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Discover"].firstMatch.waitForExistence(timeout: 15))
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'feed-post-card' AND label BEGINSWITH 'maya'")).firstMatch
        var attempts = 0
        while !card.exists && attempts < 6 { app.swipeDown(); attempts += 1 }
        XCTAssertTrue(card.waitForExistence(timeout: 10), "No Fit-Check card on the feed.")
        let carousel = card.descendants(matching: .any)["feed-photo-carousel"].firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 5), "No photo carousel on the card.")
        carousel.tap()
        XCTAssertTrue(app.descendants(matching: .any)["voteFanScreen"].waitForExistence(timeout: 10), "Vote screen did not open.")

        // Before voting the chip reads "Vote #" with no count.
        let chip = app.descendants(matching: .any)["voteFanTotalChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "Vote total chip missing.")
        XCTAssertNil(chip.label.rangeOfCharacter(from: .decimalDigits), "Count was visible before voting: \(chip.label)")
        attach(app, "4-reveal-start")

        let fan = app.descendants(matching: .any)["voteFan"]
        XCTAssertTrue(fan.waitForExistence(timeout: 5), "Photo fan missing.")
        fan.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Undo"].firstMatch.waitForExistence(timeout: 5), "No Undo toast after holding to vote.")

        // Once voted, the count is revealed and exposed to accessibility.
        let revealed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES '.*[0-9].*'"), object: chip)
        XCTAssertEqual(XCTWaiter().wait(for: [revealed], timeout: 5), .completed, "Result never revealed after voting.")
        attach(app, "5-reveal-after")
    }
}
