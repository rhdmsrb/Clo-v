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
        if !undo.waitForExistence(timeout: 3) { centre.press(forDuration: Self.holdSeconds) }
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
        attach(app, name: "vote-01-top")

        // The action row has a comment button that scrolls the comments into view.
        let commentButton = app.buttons["voteFanCommentButton"]
        XCTAssertTrue(commentButton.exists, "comment button missing from the action row")
        commentButton.tap()
        attach(app, name: "vote-02-after-comment-button")

        let input = app.textViews["voteFanCommentInput"].exists
            ? app.textViews["voteFanCommentInput"] : app.textFields["voteFanCommentInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "comment input missing")
        input.tap()
        input.typeText("Looks great on this one")
        app.buttons["voteFanCommentSend"].tap()

        app.buttons["reelBackButton"].tap()
        XCTAssertTrue(app.buttons["watchFeedButton"].firstMatch.waitForExistence(timeout: 10), "back did not return to the feed")
    }

    /// Voting happens on the post itself: press and hold the photo, see the results with Undo, take it back.
    func testHoldingThePhotoOnTheFeedCardShowsResultsThenUndoBringsBackTheHint() throws {
        let app = XCUIApplication()
        app.launchArguments += [Self.sampleDataArgument]
        app.launch()
        XCTAssertTrue(app.buttons["watchFeedButton"].firstMatch.waitForExistence(timeout: 15), "feed never appeared")
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'feed-post-card' AND label BEGINSWITH 'maya'")).firstMatch
        var attempts = 0
        while !card.exists && attempts < 6 { app.swipeDown(); attempts += 1 }
        XCTAssertTrue(card.waitForExistence(timeout: 10), "maya's post not found")

        let carousel = card.descendants(matching: .any)["feed-photo-carousel"].firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 5), "no photo carousel on the card")
        let hint = card.descendants(matching: .any)["feed-vote-hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "no press-and-hold hint on the card")
        XCTAssertFalse(card.buttons["feed-vote-button-1"].exists, "the vote buttons are gone; votes are cast on the photo")
        let results = card.descendants(matching: .any)["feed-vote-results"]
        XCTAssertFalse(results.exists, "results must stay hidden until the viewer votes")
        bringIntoOpenArea(carousel, in: app)
        waitUntilStill(carousel)
        attach(app, name: "feed-card-before-vote")

        carousel.press(forDuration: 1.2)
        XCTAssertTrue(results.waitForExistence(timeout: 5), "results did not appear after holding the photo")
        XCTAssertFalse(app.descendants(matching: .any)["voteFanScreen"].exists, "a hold must vote, not open the vote screen")
        attach(app, name: "feed-card-voted")

        let undo = card.buttons["feed-vote-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Undo on the card after voting")
        undo.tap()
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "the hint did not return after Undo")
    }

    /// A profile tile opens the post as the feed card (with its vote hint), not the vote screen.
    func testProfileTileOpensThePostAsAFeedCard() throws {
        let app = XCUIApplication()
        app.launchArguments += [Self.sampleDataArgument]
        app.launch()
        XCTAssertTrue(app.buttons["accountTab"].waitForExistence(timeout: 15), "tab bar never appeared")
        app.buttons["accountTab"].tap()

        let tile = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'My rainy day commute look'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "profile tile not found")
        tile.tap()

        let card = app.descendants(matching: .any)["feed-post-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "tapping a profile tile should show the post card")
        XCTAssertFalse(app.descendants(matching: .any)["voteFanScreen"].exists, "the vote screen must not open directly")
        attach(app, name: "profile-post-card")
    }

    // MARK: - Helpers

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// The feed pins its search/chip header over the list, so a tap on a
    /// carousel that XCUITest auto-scrolled to the very top lands on the
    /// header. Drag the list from its left margin (so the drag never starts
    /// on a card's paged carousel) until the carousel's centre sits in the
    /// open area between the header and the tab bar.
    private func bringIntoOpenArea(_ element: XCUIElement, in app: XCUIApplication) {
        let height = app.windows.firstMatch.frame.height
        let openArea = (height * 0.25)...(height * 0.8)
        for _ in 0..<12 {
            waitUntilStill(element)
            let midY = element.frame.midY
            if openArea.contains(midY) { return }
            let down = midY > openArea.upperBound
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: down ? 0.7 : 0.3))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: down ? 0.3 : 0.7))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("could not scroll the carousel into view (centre at \(element.frame.midY))")
    }

    /// A tap during scroll deceleration only stops the scroll, so wait until
    /// the element has stopped moving before interacting with it.
    private func waitUntilStill(_ element: XCUIElement) {
        var last = element.frame.midY
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.4)
            let now = element.frame.midY
            if abs(now - last) < 0.5 { return }
            last = now
        }
    }

    private func openMayasVoteScreen() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [Self.sampleDataArgument]
        app.launch()
        XCTAssertTrue(app.buttons["watchFeedButton"].firstMatch.waitForExistence(timeout: 15), "feed never appeared")
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'feed-post-card' AND label BEGINSWITH 'maya'")).firstMatch
        var attempts = 0
        while !card.exists && attempts < 6 { app.swipeDown(); attempts += 1 }
        XCTAssertTrue(card.waitForExistence(timeout: 10), "maya's post not found")
        let carousel = card.descendants(matching: .any)["feed-photo-carousel"].firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 5), "no feed carousel on maya's post")
        bringIntoOpenArea(carousel, in: app)
        // A tap that lands while the carousel is auto-advancing only stops the
        // animation, so retry rather than depend on the timing.
        let screen = app.descendants(matching: .any)["voteFanScreen"]
        var taps = 0
        while !screen.exists && taps < 3 {
            carousel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = screen.waitForExistence(timeout: 4)
            taps += 1
        }
        XCTAssertTrue(screen.exists, "vote screen did not open")
        return app
    }
}
