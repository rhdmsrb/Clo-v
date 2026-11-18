import XCTest

/// The tab bar is Home · Vote · Post · Weather · Profile. Explore and Groups are no
/// longer tabs; these helpers reach them the way a person would.
extension XCUIApplication {
    /// Explore opens as a sheet from the search button on Home.
    func openExplore(file: StaticString = #filePath, line: UInt = #line) {
        let home = buttons["feedTab"]
        XCTAssertTrue(home.waitForExistence(timeout: 15), "Home tab missing", file: file, line: line)
        home.tap()
        let search = buttons["home.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Home search button missing", file: file, line: line)
        search.tap()
    }

    /// Groups lives in the Profile menu.
    func openGroups(file: StaticString = #filePath, line: UInt = #line) {
        let profile = buttons["accountTab"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15), "Profile tab missing", file: file, line: line)
        profile.tap()
        buttons["profile.menu"].tap()
        let groups = buttons["profileShortcut_Groups"]
        XCTAssertTrue(groups.waitForExistence(timeout: 5), "Groups missing from the Profile menu", file: file, line: line)
        groups.tap()
    }
}
