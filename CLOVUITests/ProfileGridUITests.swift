import XCTest

/// The profile's Live / Ended / Saved grid keeps every tile on screen and at most half its width.
final class ProfileGridUITests: XCTestCase {
    private static let sampleDataArgument = "--uiTestSampleData"
    /// Rounding slack, in points, for frame comparisons.
    private static let tolerance: CGFloat = 1

    override func setUp() {
        continueAfterFailure = false
    }

    func testProfileTilesStayWithinHalfTheScreen() {
        let app = XCUIApplication()
        app.launchArguments = [Self.sampleDataArgument]
        app.launch()
        XCTAssertTrue(app.buttons["accountTab"].waitForExistence(timeout: 15), "tab bar never appeared")
        app.buttons["accountTab"].tap()

        let grid = app.descendants(matching: .any)["masonry-grid"].firstMatch
        var swipes = 0
        while !grid.exists && swipes < 6 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(grid.waitForExistence(timeout: 10), "no posts grid on the profile")

        let screen = app.windows.firstMatch.frame
        let tiles = grid.buttons.allElementsBoundByIndex.filter { $0.identifier != "profile.tileMenu" && $0.frame.width > 0 }
        XCTAssertFalse(tiles.isEmpty, "the grid has no tiles")
        for tile in tiles {
            let frame = tile.frame
            XCTAssertGreaterThanOrEqual(frame.minX, screen.minX - Self.tolerance, "a tile runs off the left edge: \(frame)")
            XCTAssertLessThanOrEqual(frame.maxX, screen.maxX + Self.tolerance, "a tile runs off the right edge: \(frame)")
            XCTAssertLessThanOrEqual(frame.width, screen.width / 2 + Self.tolerance, "a tile is wider than half the screen: \(frame)")
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "profile-grid"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
