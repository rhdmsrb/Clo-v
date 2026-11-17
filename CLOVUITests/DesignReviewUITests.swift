import XCTest

/// Not a real regression test. Launches the DEBUG-only offline sample-data
/// mode (`--uiTestSampleData`: fake session, canned API data, locally
/// rendered photos, zero network) and walks the main screens, attaching a
/// named screenshot at every stop (kept regardless of pass/fail) so the UI
/// can be reviewed from the resulting .xcresult bundle. Steps are tolerant:
/// a missing element is recorded as a failure but never stops the walk.
final class DesignReviewUITests: XCTestCase {
    private static let sampleDataArgument = "--uiTestSampleData"
    /// Mirrors the app's `appearance.colorScheme` setting (system / light / dark).
    private static let colorSchemeArgument = "-appearance.colorScheme"
    private static let extraLargeAccessibilitySize = "UICTContentSizeCategoryAccessibilityXL"
    private static let shortWait: TimeInterval = 5
    private static let bellWait: TimeInterval = 15
    private static let settleDelay: TimeInterval = 1

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Walks

    func testGroupFeedOpensVotingScreen() {
        let app = launchApp()
        let groups = app.buttons["groupsTab"]
        XCTAssertTrue(groups.waitForExistence(timeout: 10))
        groups.tap()
        let group = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sunday Stylists'")).firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 10))
        group.tap()
        XCTAssertTrue(app.staticTexts["Sunday Stylists"].firstMatch.waitForExistence(timeout: 10))
        let post = app.buttons["groupFeed.card"].firstMatch
        XCTAssertTrue(post.waitForExistence(timeout: 10))
        post.tap()
        XCTAssertTrue(app.buttons["reelBackButton"].waitForExistence(timeout: 10))
        app.buttons["reelBackButton"].tap()
        XCTAssertTrue(app.buttons["groupFeed.card"].firstMatch.waitForExistence(timeout: 10))
    }

    func testExploreSearchAcceptsText() {
        let app = launchApp()
        app.buttons["searchTab"].tap()
        let field = app.textFields["search.query"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("fit")
        XCTAssertEqual(field.value as? String, "fit")
    }

    func testWalkMainScreens() {
        let app = launchApp()
        walkFeed(app, prefix: "feed")
        walkSwipeFeed(app)
        walkNotifications(app)
        walkAccount(app)
        walkCreate(app)
        walkSearch(app)
    }

    func testWalkLargeDynamicType() {
        let app = launchApp(arguments: ["-UIPreferredContentSizeCategoryName", Self.extraLargeAccessibilitySize])
        attach(app, name: "ax-01-feed")
        scroll(app)
        attach(app, name: "ax-02-feed-scrolled")
        scrollToTop(app)
        openCommentSheet(app, prefix: "ax")
        openVoteScreen(app, prefix: "ax")
        dismissSheet(app)
        tapTab(app, "searchTab", shot: "ax-04-search-tab")
        tapTab(app, "accountTab", shot: "ax-05-account-tab")
        tapTab(app, "feedTab", shot: "ax-06-feed-tab-bar")
    }

    func testWalkDarkMode() {
        // `-AppleInterfaceStyle` is ignored on iOS, so the walk was light. The
        // app's own appearance setting (read from the launch arguments) is what works.
        let app = launchApp(arguments: [Self.colorSchemeArgument, "dark"])
        walkFeed(app, prefix: "dark-feed")
        walkNotifications(app, prefix: "dark")
        walkAccount(app, prefix: "dark")
        walkSearch(app, prefix: "dark")
    }

    // MARK: - Steps

    private func walkFeed(_ app: XCUIApplication, prefix: String) {
        attach(app, name: "\(prefix)-01-top")
        scroll(app)
        attach(app, name: "\(prefix)-02-scrolled")
        scroll(app, up: false, times: 2)

        openCommentSheet(app, prefix: prefix)
        openVoteScreen(app, prefix: prefix)
    }

    /// Voting opens the "why did you vote" sheet, which doubles as the
    /// comment sheet stop.
    private func voteOnFirstLook(_ app: XCUIApplication, prefix: String) {
        guard let look = scrollToVisible(app, buttons(app, labeled: "Look 1")) else {
            attach(app, name: "\(prefix)-03-vote-missing"); return
        }
        attach(app, name: "\(prefix)-03a-before-vote")
        guard tap(look) else {
            attach(app, name: "\(prefix)-03-vote-missing"); return
        }
        confirmVoteIfAsked(app)
        settle()
        attach(app, name: "\(prefix)-03-comment-sheet")
        dismissSheet(app)
        attach(app, name: "\(prefix)-03-after-vote")
    }

    /// Voting now asks "Vote for Look N?" first; accept it when it appears.
    private func confirmVoteIfAsked(_ app: XCUIApplication) {
        let confirm = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Vote for Look'")).firstMatch
        if confirm.waitForExistence(timeout: 2) { confirm.tap() }
    }

    /// The feed's Comment button opens a half-height comment sheet (not the
    /// vote screen). Capture it, then dismiss it by swiping its photo fan down.
    private func openCommentSheet(_ app: XCUIApplication, prefix: String) {
        // Scroll the button into the band above the floating tab bar first: at
        // large text sizes its centre sits behind the bar, and the tap would
        // land on the tab bar's + button and open Create instead.
        let sheetFan = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label ENDSWITH 'in this Fit-Check'")).firstMatch
        guard let comment = scrollToVisible(app, app.buttons.matching(identifier: "feed-comment-button")),
              tap(comment), sheetFan.waitForExistence(timeout: Self.shortWait) else {
            attach(app, name: "\(prefix)-comment-sheet-missing"); return
        }
        settle()
        attach(app, name: "\(prefix)-comment-sheet")
        sheetFan.swipeDown(velocity: .fast)
        settle()
    }

    /// Tapping the feed photos opens the vote screen; its action row has a
    /// comment button that scrolls to the comments.
    private func openVoteScreen(_ app: XCUIApplication, prefix: String) {
        guard let photos = scrollToVisible(app, app.buttons.matching(identifier: "feed-photo-carousel")),
              tap(photos), app.buttons["reelBackButton"].waitForExistence(timeout: Self.shortWait) else {
            attach(app, name: "\(prefix)-vote-screen-missing"); return
        }
        attach(app, name: "\(prefix)-vote-screen")
        if tap(app.buttons["voteFanCommentButton"]) {
            settle()
            attach(app, name: "\(prefix)-vote-comments")
        }
        _ = tap(app.buttons["reelBackButton"])
        settle()
    }

    private func openPhotoZoom(_ app: XCUIApplication, prefix: String) {
        guard let zoom = scrollToVisible(app, buttons(app, labeled: "Zoom look 1")), tap(zoom) else { attach(app, name: "\(prefix)-04-zoom-missing"); return }
        settle()
        attach(app, name: "\(prefix)-04-photo-zoom")
        // The close "X" sits at the top-right of the zoom cover.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.11)).tap()
        settle()
        attach(app, name: "\(prefix)-04b-after-zoom-close")
    }

    private func openFirstDetail(_ app: XCUIApplication, prefix: String) {
        let links = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'comment'"))
        guard let link = scrollToVisible(app, links), tap(link) else { attach(app, name: "\(prefix)-05-detail-missing"); return }
        settle()
        attach(app, name: "\(prefix)-05-detail")
        scroll(app)
        attach(app, name: "\(prefix)-06-detail-scrolled")
        goBack(app)
    }

    private func walkSwipeFeed(_ app: XCUIApplication) {
        tapTab(app, "feedTab", shot: nil)
        let watch = app.buttons["watchFeedButton"]
        guard tap(watch) else { attach(app, name: "swipe-00-missing"); return }
        settle()
        attach(app, name: "swipe-01-for-you")
        let following = app.buttons["Following"].firstMatch
        if tap(following) { settle(); attach(app, name: "swipe-02-following") }
        let forYou = app.buttons["For You"].firstMatch
        _ = tap(forYou)
        app.swipeUp()
        settle()
        attach(app, name: "swipe-03-next")
        // The swipe feed has no close control while it shows items; the
        // selected tab is the only way back (reported as a UX finding).
        tapTab(app, "feedTab", shot: "swipe-04-after-feed-tab")
        if !app.buttons["watchFeedButton"].firstMatch.exists {
            attach(app, name: "swipe-05-still-in-swipe-feed")
            let explore = app.buttons["Explore Fit-Checks"]
            _ = tap(explore)
        }
    }

    private func walkNotifications(_ app: XCUIApplication, prefix: String = "notif") {
        tapTab(app, "feedTab", shot: nil)
        scrollToTop(app)
        let bell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Notifications'")).firstMatch
        // The feed reloads after a tab switch, so the header can take longer than
        // `shortWait` to reappear on a slow simulator.
        _ = bell.waitForExistence(timeout: Self.bellWait)
        guard tap(bell) else { attach(app, name: "\(prefix)-00-bell-missing"); return }
        settle()
        attach(app, name: "\(prefix)-01-notifications")
        let unread = app.buttons["Unread"].firstMatch
        if tap(unread) { settle(); attach(app, name: "\(prefix)-02-unread") }
        goBack(app)
    }

    private func walkSearch(_ app: XCUIApplication, prefix: String = "search") {
        tapTab(app, "searchTab", shot: "\(prefix)-01-tab")
        let field = app.textFields["search.query"]
        if field.waitForExistence(timeout: Self.shortWait) { attach(app, name: "\(prefix)-02-search") }
    }

    private func walkAccount(_ app: XCUIApplication, prefix: String = "account") {
        tapTab(app, "accountTab", shot: "\(prefix)-01-tab")
        scroll(app)
        attach(app, name: "\(prefix)-02-scrolled")
        scroll(app, up: false, times: 2)

        openShortcut(app, "Wardrobe", shot: "\(prefix)-03-wardrobe")
        goBack(app)
        openShortcut(app, "Groups", shot: "\(prefix)-04-groups")
        let group = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Sunday Stylists'")).firstMatch
        if tap(group) { settle(); attach(app, name: "\(prefix)-05-group-detail"); scroll(app); attach(app, name: "\(prefix)-06-group-detail-scrolled"); goBack(app) }
        goBack(app)
        openShortcut(app, "Friends", shot: "\(prefix)-07-friends")
        goBack(app)
        if tap(app.buttons["profile.menu"]), tap(app.buttons["yourWeekButton"]) { settle(); attach(app, name: "\(prefix)-08-your-week"); goBack(app) }
    }

    private func walkCreate(_ app: XCUIApplication) {
        guard tap(app.buttons["tabPlusButton"]) else { attach(app, name: "create-00-missing"); return }
        settle()
        attach(app, name: "create-01-sheet")
        scroll(app)
        attach(app, name: "create-02-scrolled")
        _ = tap(app.buttons["createCloseButton"])
        settle()
    }

    // MARK: - Helpers

    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [Self.sampleDataArgument] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["feedSearchButton"].firstMatch.waitForExistence(timeout: 10),
                      "Sample-data feed never appeared")
        settle()
        return app
    }

    private func openShortcut(_ app: XCUIApplication, _ title: String, shot: String) {
        // Shortcuts live in the Profile menu; open it first.
        _ = tap(app.buttons["profile.menu"])
        let row = app.buttons["profileShortcut_\(title)"].firstMatch
        let fallback = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        if !tap(row) && !tap(fallback) { attach(app, name: "\(shot)-missing"); return }
        settle()
        attach(app, name: shot)
    }

    private func tapTab(_ app: XCUIApplication, _ identifier: String, shot: String?) {
        let tab = app.buttons[identifier]
        XCTAssertTrue(tab.waitForExistence(timeout: Self.shortWait), "\(identifier) missing")
        _ = tap(tab)
        settle()
        if let shot { attach(app, name: shot) }
    }

    @discardableResult
    private func tap(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: Self.shortWait) else { return false }
        // Calling `isHittable` on an element that is mid-scroll or not laid out yet
        // raises "Failed to determine hittability", so wait for its centre to sit
        // inside the window and tap that point instead.
        let window = XCUIApplication().windows.firstMatch.frame
        let deadline = Date().addingTimeInterval(Self.shortWait)
        func isOnScreen() -> Bool {
            let frame = element.frame
            return !frame.isEmpty && window.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        while !isOnScreen() && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        guard isOnScreen() else { return false }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
        settle()
    }

    private func dismissSheet(_ app: XCUIApplication) {
        let skip = app.buttons["Skip"].firstMatch
        if skip.exists { skip.tap(); settle() }
    }

    private func scroll(_ app: XCUIApplication, up: Bool = true, times: Int = 1) {
        for _ in 0..<times { up ? app.swipeUp() : app.swipeDown() }
        settle()
    }

    /// Scrolls from the top in short steps until some match of `query` sits in
    /// the visible band above the floating tab bar, and returns that match.
    private func scrollToVisible(_ app: XCUIApplication, _ query: XCUIElementQuery, maxSteps: Int = 14) -> XCUIElement? {
        let window = app.windows.firstMatch.frame
        func visibleMatch() -> XCUIElement? {
            // The lazy feed drops off-screen cards while we scroll, so an element
            // from an earlier snapshot can vanish; reading its frame would then
            // fail the test. Re-check each element right before using it.
            for index in 0..<query.count {
                let element = query.element(boundBy: index)
                guard element.exists else { continue }
                let frame = element.frame
                if frame.height > 0 && frame.minY > window.height * 0.12 && frame.maxY < window.height * 0.8 {
                    return element
                }
            }
            return nil
        }
        scrollToTop(app)
        for _ in 0..<maxSteps {
            if let match = visibleMatch() { return match }
            smallScroll(app)
        }
        return visibleMatch()
    }

    private func buttons(_ app: XCUIApplication, labeled label: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label == %@", label))
    }

    /// A short drag (about a quarter screen) so targets are not overshot.
    private func smallScroll(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func scrollToTop(_ app: XCUIApplication, swipes: Int = 8) {
        for _ in 0..<swipes { app.swipeDown() }
        settle()
    }

    private func settle() { Thread.sleep(forTimeInterval: Self.settleDelay) }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
