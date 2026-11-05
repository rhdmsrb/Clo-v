import XCTest
@testable import CLOV

final class RecentSearchesTests: XCTestCase {
    func testAddingPutsNewestFirst() {
        let searches = RecentSearches().adding("wedding guest").adding("interview")
        XCTAssertEqual(searches.terms, ["interview", "wedding guest"])
    }

    func testAddingAnExistingTermMovesItToFrontIgnoringCase() {
        let searches = RecentSearches().adding("Date night").adding("brunch").adding("date NIGHT")
        XCTAssertEqual(searches.terms, ["date NIGHT", "brunch"])
    }

    func testListIsCappedAtTheLimitDroppingTheOldest() {
        let terms = (1...12).map { "look \($0)" }
        let searches = terms.reduce(RecentSearches()) { $0.adding($1) }
        XCTAssertEqual(searches.terms.count, RecentSearches.limit)
        XCTAssertEqual(searches.terms.first, "look 12")
        XCTAssertFalse(searches.terms.contains("look 1"))
    }

    func testBlankAndSingleCharacterTermsAreIgnored() {
        let searches = RecentSearches().adding("   ").adding("a").adding("")
        XCTAssertTrue(searches.terms.isEmpty)
    }

    func testTermsAreSanitizedLikeLiveSearch() {
        XCTAssertEqual(RecentSearches().adding("  a),(b \n").terms, ["ab"])
    }

    func testRemovingDropsOnlyThatTerm() {
        let searches = RecentSearches().adding("one two").adding("three four").removing("ONE TWO")
        XCTAssertEqual(searches.terms, ["three four"])
    }

    func testClearedIsEmpty() {
        XCTAssertTrue(RecentSearches().adding("brunch").cleared().terms.isEmpty)
    }

    func testAddingDoesNotMutateTheOriginal() {
        let original = RecentSearches().adding("brunch")
        _ = original.adding("travel")
        XCTAssertEqual(original.terms, ["brunch"])
    }
}

final class RecentSearchStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "RecentSearchStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testSavedSearchesRoundTrip() {
        let store = RecentSearchStore(defaults: defaults)
        let user = UUID()
        store.save(RecentSearches().adding("wedding guest").adding("brunch"), for: user)
        XCTAssertEqual(store.load(for: user).terms, ["brunch", "wedding guest"])
    }

    func testEachUserHasTheirOwnList() {
        let store = RecentSearchStore(defaults: defaults)
        let first = UUID(), second = UUID()
        store.save(RecentSearches().adding("brunch"), for: first)
        XCTAssertTrue(store.load(for: second).terms.isEmpty)
    }

    func testCorruptStoredDataLoadsAsEmpty() {
        let store = RecentSearchStore(defaults: defaults)
        let user = UUID()
        defaults.set(Data("not json".utf8), forKey: store.key(for: user))
        XCTAssertTrue(store.load(for: user).terms.isEmpty)
    }
}
