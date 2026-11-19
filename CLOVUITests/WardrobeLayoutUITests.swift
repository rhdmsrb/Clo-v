import XCTest

/// Wardrobe cards must form an even grid: every card the same width and height,
/// and cards in a row lined up, whatever details (wear count, brand, tags) each item has.
final class WardrobeLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWardrobeCardsFormAnEvenGrid() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--uiTestSampleData", "-appearance.paletteID", "clay"]
        app.launch()
        app.buttons["accountTab"].tap()
        app.buttons["profile.menu"].tap()
        app.buttons["profileShortcut_Wardrobe"].tap()

        let cards = app.descendants(matching: .any).matching(identifier: "wardrobe.card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10), "No wardrobe cards.")
        Thread.sleep(forTimeInterval: 1.5)
        attach(app, "wardrobe-top")

        let visible = (0..<cards.count).map { cards.element(boundBy: $0) }.filter(\.isHittable)
        XCTAssertGreaterThanOrEqual(visible.count, 2, "Need at least two cards on screen to compare.")
        let first = visible[0].frame
        for card in visible.dropFirst() {
            XCTAssertEqual(card.frame.width, first.width, accuracy: 1, "Cards differ in width.")
            XCTAssertEqual(card.frame.height, first.height, accuracy: 1, "Cards differ in height.")
        }
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        attach(app, "wardrobe-scrolled")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
