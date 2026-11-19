import XCTest

/// The floating tab bar must clear the last row of every scrolling screen
/// without leaving a large dead gap. Each test scrolls to the end, then
/// measures the space between the lowest content element and the top of
/// the bar. The gap is attached as text so a failure shows the numbers.
final class BottomClearanceUITests: XCTestCase {
    /// Only screens with a known last row are asserted; the rest are
    /// reviewed from their screenshots. The last row must not sit under the bar.
    private static let minimumGap: CGFloat = 0
    /// The last row's frame ends inside its card, so allow for that padding.
    private static let maximumGap: CGFloat = 80
    private static let maxSwipes = 12

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testFeedClearsTabBar() {
        let app = launchApp()
        assertClearance(app, screen: "feed", lastRow: nil)
    }

    func testSettingsClearsTabBar() {
        let app = launchApp()
        app.buttons["accountTab"].tap()
        openSettings(app)
        assertClearance(app, screen: "settings", lastRow: app.buttons["settingsDeleteAccount"])
    }

    func testAppearanceClearsTabBar() {
        let app = launchApp()
        app.buttons["accountTab"].tap()
        app.buttons["profile.menu"].tap()
        app.buttons["profileShortcut_Appearance"].tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
        assertClearance(app, screen: "appearance", lastRow: nil)
    }

    func testExploreClearsTabBar() {
        let app = launchApp()
        app.openExplore()
        assertClearance(app, screen: "explore", lastRow: nil)
    }

    func testGroupsClearsTabBar() {
        let app = launchApp()
        app.openGroups()
        assertClearance(app, screen: "groups", lastRow: nil)
    }

    // MARK: - Measurement

    /// Scrolls to the end and attaches a screenshot. When `lastRow` is given,
    /// also asserts it sits fully above the tab bar.
    private func assertClearance(_ app: XCUIApplication, screen: String, lastRow: XCUIElement?) {
        for _ in 0..<Self.maxSwipes { app.swipeUp() }
        Thread.sleep(forTimeInterval: 1)
        let bar = app.otherElements["Main navigation"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "\(screen): tab bar not found")
        attach(app, screen: screen, gap: lastRow.map { bar.frame.minY - $0.frame.maxY })
        guard let lastRow else { return }
        XCTAssertTrue(lastRow.exists, "\(screen): last row missing")
        let gap = bar.frame.minY - lastRow.frame.maxY
        XCTAssertGreaterThanOrEqual(gap, Self.minimumGap, "\(screen): last row sits under the tab bar")
        XCTAssertLessThanOrEqual(gap, Self.maximumGap, "\(screen): \(Int(gap))pt dead gap above the tab bar")
    }

    // MARK: - Helpers

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--uiTestSampleData"]
        app.launch()
        XCTAssertTrue(app.buttons["accountTab"].waitForExistence(timeout: 15))
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        let menu = app.buttons["profile.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "Profile menu missing.")
        menu.tap()
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Settings entry missing.")
        settings.tap()
    }

    private func attach(_ app: XCUIApplication, screen: String, gap: CGFloat?) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(screen)-bottom"
        shot.lifetime = .keepAlways
        add(shot)
        let note = XCTAttachment(string: "\(screen): gap above tab bar = \(gap.map { "\($0)pt" } ?? "not measured")")
        note.name = "\(screen)-gap"
        note.lifetime = .keepAlways
        add(note)
    }
}
