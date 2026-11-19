import XCTest

/// Reaching Explore and Groups through their tabs (Feed · Group · Post · Search · Profile).
extension XCUIApplication {
    func openExplore(file: StaticString = #filePath, line: UInt = #line) {
        let search = buttons["searchTab"]
        XCTAssertTrue(search.waitForExistence(timeout: 15), "Search tab missing", file: file, line: line)
        search.tap()
    }

    func openGroups(file: StaticString = #filePath, line: UInt = #line) {
        let groups = buttons["groupsTab"]
        XCTAssertTrue(groups.waitForExistence(timeout: 15), "Group tab missing", file: file, line: line)
        groups.tap()
    }
}
