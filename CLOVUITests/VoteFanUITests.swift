import XCTest
import UIKit

/// Offline sample-data walk of the vote screen: photo fan, hold to vote,
/// early release, Undo, and posting a comment. Uses Maya's post, which is
/// live and not yet voted on by the sample viewer.
final class VoteFanUITests: XCTestCase {
    private static let sampleDataArgument = "--uiTestSampleData"
    private static let holdSeconds: TimeInterval = 1.2
    private static let earlyReleaseSeconds: TimeInterval = 0.2
    /// Past one 3 s carousel interval but inside the card's 5 s stay on the picked look.
    private static let voteDwellCheckSeconds: TimeInterval = 3.8

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Tests

    func testTappingFeedPhotoStaysOnFeed() {
        let app = XCUIApplication()
        app.launchArguments = [Self.sampleDataArgument]
        app.launch()

        let carousel = app.descendants(matching: .any)["feed-photo-carousel"].firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 15))
        bringIntoOpenArea(carousel, in: app)
        carousel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertFalse(app.descendants(matching: .any)["voteFanScreen"].waitForExistence(timeout: 2))
        XCTAssertTrue(carousel.exists)
        XCTAssertTrue(app.buttons["feedTab"].isHittable)
    }

    func testCompareVotesWithoutLeavingFeed() {
        let app = XCUIApplication()
        app.launchArguments = [Self.sampleDataArgument]
        app.launch()
        let compare = app.buttons["feed.compare"].firstMatch
        XCTAssertTrue(compare.waitForExistence(timeout: 10))
        compare.tap()
        XCTAssertFalse(app.buttons["Enlarge look 1"].exists)
        let vote = app.buttons["feed.vote.0"].firstMatch
        XCTAssertTrue(vote.waitForExistence(timeout: 5))
        vote.tap()
        XCTAssertTrue(app.buttons["Undo vote"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["feedTab"].exists)
    }

    func testQuickPostRequiresAnAudienceChoice() {
        let app = XCUIApplication()
        app.launchArguments = [Self.sampleDataArgument, "--uiTestCreatePhotos"]
        app.launch()
        app.buttons["tabPlusButton"].tap()
        app.buttons["createNextButton"].tap()
        let quickPost = app.buttons["createQuickPost"]
        XCTAssertTrue(quickPost.waitForExistence(timeout: 5))
        XCTAssertFalse(quickPost.isEnabled)
        let everyone = app.buttons["Everyone"].firstMatch
        for _ in 0..<4 where !everyone.isHittable { app.swipeUp() }
        XCTAssertTrue(everyone.isHittable)
        everyone.tap()
        XCTAssertTrue(quickPost.isEnabled)
    }

    func testLandscapePhotoFillsTheFeedCardWithoutBars() throws {
        let app = XCUIApplication()
        app.launchArguments += [Self.sampleDataArgument, "--uiTestWidePhoto"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["feed-post-card"].firstMatch.waitForExistence(timeout: 15))
        let carousel = app.descendants(matching: .any)["feed-photo-carousel"].firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 10))
        bringIntoOpenArea(carousel, in: app, centered: true)
        let frame = carousel.frame
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.height, 0)
        // A wide image fills the tall post (cropped at the sides), so there are no black bars
        // above or below it. The center must contain image pixels so a loading placeholder cannot pass.
        var fitted = false
        for _ in 0..<10 {
            let screenshot = XCUIScreen.main.screenshot().image
            let x = frame.midX - window.minX
            let top = CGPoint(x: x, y: frame.minY - window.minY + frame.height * 0.2)
            let middle = CGPoint(x: x, y: frame.midY - window.minY)
            let bottom = CGPoint(x: x, y: frame.minY - window.minY + frame.height * 0.8)
            if let topRGB = pixel(in: screenshot, at: top), let centerRGB = pixel(in: screenshot, at: middle),
               let bottomRGB = pixel(in: screenshot, at: bottom),
               !topRGB.allSatisfy({ $0 < 30 }), !bottomRGB.allSatisfy({ $0 < 30 }),
               centerRGB.contains(where: { $0 > 60 }) {
                fitted = true
                break
            }
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)], timeout: 0.5)
        }
        XCTAssertTrue(fitted, "landscape photo should fill the post with no black bars")
    }

    private func pixel(in image: UIImage, at point: CGPoint) -> [UInt8]? {
        guard let cg = image.cgImage else { return nil }
        let x = Int(point.x * image.scale)
        let y = Int(point.y * image.scale)
        guard x >= 0, y >= 0, x < cg.width, y < cg.height,
              let pixel = cg.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Array(bytes.prefix(3))
    }

    func testEarlyReleaseDoesNotVoteAndHoldVotesThenUndoRetracts() throws {
        let app = openMayasVoteScreen()
        let fan = app.descendants(matching: .any)["voteFan"]
        XCTAssertTrue(fan.waitForExistence(timeout: 5), "photo fan missing")
        let centre = fan.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let undo = app.buttons["Undo"].firstMatch

        // The server summary must finish before voting is enabled.
        let loading = app.descendants(matching: .any)["vote.summaryLoading"]
        if loading.exists { XCTAssertTrue(waitUntilGone(loading, timeout: 10), "vote state did not finish loading") }
        XCTAssertFalse(app.buttons["vote.summaryRetry"].exists, "vote state failed to load")

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
        XCTAssertFalse(app.buttons["feedTab"].isHittable, "floating tab bar should be hidden on the vote screen")
        attach(app, name: "vote-01-top")

        // Comments open as a separate sheet without revealing the vote total.
        let count = app.descendants(matching: .any)["voteFanTotalChip"]
        XCTAssertTrue(count.exists)
        XCTAssertNil(count.label.rangeOfCharacter(from: .decimalDigits), "results must stay hidden before voting")
        let commentButton = app.buttons["voteFanCommentButton"]
        XCTAssertTrue(commentButton.exists, "comment button missing from the action row")
        commentButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["voteFanComments"].waitForExistence(timeout: 5), "comment sheet missing")
        XCTAssertTrue(app.buttons["voteFanCommentSend"].waitForExistence(timeout: 10), "send button missing")
        attach(app, name: "vote-02-after-comment-button")

        let input = app.textViews["voteFanCommentInput"].exists
            ? app.textViews["voteFanCommentInput"] : app.textFields["voteFanCommentInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "comment input missing")
        input.tap()
        input.typeText("Looks great on this one")
        app.buttons["voteFanCommentSend"].tap()
        let close = app.buttons["comments.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(waitUntilGone(close, timeout: 5))

        XCTAssertTrue(app.buttons["reelBackButton"].waitForExistence(timeout: 5))
        XCTAssertNil(count.label.rangeOfCharacter(from: .decimalDigits), "comments must not reveal results")
        app.buttons["reelBackButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["feed-post-card"].firstMatch.waitForExistence(timeout: 10), "back did not return to the feed")
    }

    /// Voting happens on the post itself: press and hold the photo, see the results with Undo, take it back.
    func testHoldingThePhotoOnTheFeedCardShowsResultsThenUndoBringsBackTheHint() throws {
        let app = XCUIApplication()
        app.launchArguments += [Self.sampleDataArgument]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["feed-post-card"].firstMatch.waitForExistence(timeout: 15), "feed never appeared")
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
        let photoHint = card.descendants(matching: .any)["feed-photo-hold-hint"]
        XCTAssertTrue(photoHint.waitForExistence(timeout: 5),
                      "the photo itself must say how to vote; the hint below it is under the fold")
        bringIntoOpenArea(carousel, in: app)
        waitUntilStill(carousel)
        attach(app, name: "feed-card-before-vote")

        carousel.press(forDuration: 1.2)
        let pressFinishedAt = ProcessInfo.processInfo.systemUptime
        let centredResult = card.descendants(matching: .any)["feed-photo-result"]
        XCTAssertTrue(centredResult.waitForExistence(timeout: 5), "the shown photo's result is not centred on the photo after voting")
        let showsOwnPick = NSPredicate(format: "label CONTAINS 'your vote'")
        XCTAssertTrue(showsOwnPick.evaluate(with: centredResult), "right after voting the photo should show the viewer's pick")
        attach(app, name: "feed-card-voted")
        // Measure from the press so accessibility queries and attachments do not extend the wait.
        let remainingDwellCheck = Self.voteDwellCheckSeconds - (ProcessInfo.processInfo.systemUptime - pressFinishedAt)
        if remainingDwellCheck > 0 { Thread.sleep(forTimeInterval: remainingDwellCheck) }
        XCTAssertTrue(showsOwnPick.evaluate(with: centredResult),
                      "the carousel moved off the picked look right after the vote")
        attach(app, name: "feed-card-voted-after-dwell")
        XCTAssertTrue(results.exists, "results did not appear after holding the photo")
        XCTAssertFalse(app.descendants(matching: .any)["voteFanScreen"].exists, "a hold must vote, not open the vote screen")
        XCTAssertTrue(photoHint.waitForNonExistence(timeout: 5), "the hold hint stayed on the photo after voting")

        let undo = card.buttons["feed-vote-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Undo on the card after voting")
        undo.tap()
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "the hint did not return after Undo")
        XCTAssertTrue(centredResult.waitForNonExistence(timeout: 5), "the centred result stayed on the photo after Undo")
    }

    /// The full-screen vote screen is hidden for now: tapping a feed photo stays on the feed.
    func testTappingTheFeedPhotoDoesNotOpenTheVoteScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += [Self.sampleDataArgument]
        app.launch()
        let carousel = app.descendants(matching: .any)["feed-photo-carousel"].firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 15), "no photo on the feed")
        carousel.tap()
        XCTAssertFalse(app.descendants(matching: .any)["voteFanScreen"].waitForExistence(timeout: 3),
                       "the vote screen is hidden and must not open")
        XCTAssertTrue(carousel.exists, "tapping the photo should stay on the feed")
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

    /// Drag the list from its left margin (so the drag never starts
    /// on a card's paged carousel) until the carousel's centre sits in the
    /// open area between the header and the tab bar.
    private func bringIntoOpenArea(_ element: XCUIElement, in app: XCUIApplication, centered: Bool = false) {
        let height = app.windows.firstMatch.frame.height
        let openArea = centered ? (height * 0.43)...(height * 0.62) : (height * 0.25)...(height * 0.8)
        for _ in 0..<16 {
            waitUntilStill(element)
            let midY = element.frame.midY
            if openArea.contains(midY) { return }
            let down = midY > openArea.upperBound
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: down ? 0.7 : 0.3))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: down ? 0.3 : 0.7))
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
        app.launchArguments += [Self.sampleDataArgument, "--uiTestEnableFitCheckReel"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["feed-post-card"].firstMatch.waitForExistence(timeout: 15), "feed never appeared")
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
