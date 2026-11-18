import XCTest
import UIKit

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
        let undo = app.buttons["Undo vote"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["feedTab"].exists)
        attach(app, name: "feed-comparison-voted")

        undo.tap()
        XCTAssertTrue(vote.waitForExistence(timeout: 5))
        XCTAssertFalse(undo.exists)
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
        attach(app, name: "create-details-before-audience")

        app.buttons["createAudience.public"].tap()
        XCTAssertTrue(quickPost.isEnabled)
        let audience = app.staticTexts["createAudienceSummary"]
        XCTAssertTrue(audience.label.contains("Everyone"))
        attach(app, name: "create-details-everyone")

        app.buttons["createAudience.private"].tap()
        XCTAssertTrue(quickPost.isEnabled)
        XCTAssertTrue(audience.label.contains("Only me"))
        app.buttons["createSkipPhotoDetails"].tap()
        XCTAssertTrue(app.buttons["createUploadButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(audience.label.contains("Only me"))
        attach(app, name: "create-preview-private")
    }

    func testLandscapePhotoFitsInsideFeedCard() throws {
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
        // A wide image inside the taller post has padding above and below it.
        // The center must contain image pixels so a loading placeholder cannot pass.
        var fitted = false
        for _ in 0..<10 {
            let screenshot = XCUIScreen.main.screenshot().image
            let x = frame.midX - window.minX
            let top = CGPoint(x: x, y: frame.minY - window.minY + frame.height * 0.2)
            let middle = CGPoint(x: x, y: frame.midY - window.minY)
            let bottom = CGPoint(x: x, y: frame.minY - window.minY + frame.height * 0.8)
            if let topRGB = pixel(in: screenshot, at: top), let centerRGB = pixel(in: screenshot, at: middle),
               let bottomRGB = pixel(in: screenshot, at: bottom),
               topRGB.allSatisfy({ $0 < 30 }), bottomRGB.allSatisfy({ $0 < 30 }),
               centerRGB.contains(where: { $0 > 60 }) {
                fitted = true
                break
            }
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)], timeout: 0.5)
        }
        XCTAssertTrue(fitted, "landscape photo should remain fully visible with padding")
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

    func testVoteScreenShowsFanCommentsAndAcceptsACommentAtLargeTextSize() throws {
        let app = openMayasVoteScreen(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
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

    private func openMayasVoteScreen(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [Self.sampleDataArgument, "--uiTestEnableFitCheckReel"] + arguments
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
