import XCTest

/// Offline sample-data walk of the vote screen: photo fan, hold to vote,
/// early release, Undo, and posting a comment. Uses Maya's post, which is
/// live and not yet voted on by the sample viewer.
final class VoteFanUITests: XCTestCase {
    private static let sampleDataArgument = "--uiTestSampleData"
    private static let holdSeconds: TimeInterval = 1.2
    private static let earlyReleaseSeconds: TimeInterval = 0.2

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Tests

    func testEarlyReleaseDoesNotVoteAndHoldVotesThenUndoRetracts() throws {
        let app = openMayasVoteScreen()
        let fan = app.descendants(matching: .any)["voteFan"]
        XCTAssertTrue(fan.waitForExistence(timeout: 5), "photo fan missing")
        let centre = fan.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let undo = app.buttons["Undo"].firstMatch

        // Releasing early must not cast a vote.
        centre.press(forDuration: Self.earlyReleaseSeconds)
        XCTAssertFalse(undo.waitForExistence(timeout: 2), "a short press must not vote")

        // A full hold votes and shows the Undo toast.
        centre.press(forDuration: Self.holdSeconds)
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Undo toast after holding to vote")

        // Undo clears the toast and retracts the vote.
        undo.tap()
        XCTAssertTrue(waitUntilGone(undo, timeout: 5), "Undo toast did not go away")

        // Only a retracted vote can be cast again, so a second hold proves the retract.
        centre.press(forDuration: Self.holdSeconds)
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "could not vote again after Undo, so the vote was not retracted")
    }

    func testVoteScreenShowsFanCommentsAndAcceptsAComment() throws {
        let app = openMayasVoteScreen()
        XCTAssertTrue(app.descendants(matching: .any)["voteFan"].waitForExistence(timeout: 5), "photo fan missing")
        XCTAssertTrue(app.descendants(matching: .any)["voteFanComments"].exists, "comments panel missing")
        XCTAssertTrue(app.buttons["voteFanCommentSend"].exists, "send button missing")
        XCTAssertFalse(app.buttons["feedTab"].isHittable, "floating tab bar should be hidden on the vote screen")

        let input = app.textViews["voteFanCommentInput"].exists
            ? app.textViews["voteFanCommentInput"] : app.textFields["voteFanCommentInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "comment input missing")
        input.tap()
        input.typeText("Looks great on this one")
        app.buttons["voteFanCommentSend"].tap()

        app.buttons["reelBackButton"].tap()
        XCTAssertTrue(app.staticTexts["Discover"].firstMatch.waitForExistence(timeout: 10), "back did not return to the feed")
    }

    // MARK: - Helpers

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func openMayasVoteScreen() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [Self.sampleDataArgument]
        app.launch()
        XCTAssertTrue(app.staticTexts["Discover"].firstMatch.waitForExistence(timeout: 15), "feed never appeared")
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'feed-post-card' AND label BEGINSWITH 'maya'")).firstMatch
        var attempts = 0
        while !card.exists && attempts < 6 { app.swipeDown(); attempts += 1 }
        XCTAssertTrue(card.waitForExistence(timeout: 10), "maya's post not found")
        let carousel = card.descendants(matching: .any)["feed-photo-carousel"].firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 5), "no feed carousel on maya's post")
        carousel.tap()
        XCTAssertTrue(app.descendants(matching: .any)["voteFanScreen"].waitForExistence(timeout: 10), "vote screen did not open")
        return app
    }
}
