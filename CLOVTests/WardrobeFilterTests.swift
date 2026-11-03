import XCTest
@testable import CLOV

final class WardrobeFilterTests: XCTestCase {
    private func item(_ name: String?, category: String = "top", season: String? = nil, brand: String? = nil,
                      color: String? = nil, tags: [String]? = nil, frequency: String? = nil,
                      created: TimeInterval = 0) -> WardrobeItem {
        WardrobeItem(id: UUID(), ownerId: UUID(), imageUrl: "", name: name, category: category,
                     subcategory: nil, color: color, season: season, brand: brand, wearFrequency: frequency,
                     tags: tags, createdAt: Date(timeIntervalSince1970: created), updatedAt: nil)
    }

    func testNoCriteriaReturnsEverything() {
        let items = [item("A"), item("B", category: "shoes")]
        XCTAssertEqual(WardrobeFilter().apply(to: items).count, 2)
    }

    func testSearchMatchesNameBrandColorAndTagsCaseInsensitively() {
        let byName = item("Linen Shirt"), byBrand = item("x", brand: "Zara"), byColor = item("y", color: "Navy")
        let byTag = item("z", tags: ["Casual"]), other = item("Boots", category: "shoes")
        let all = [byName, byBrand, byColor, byTag, other]
        XCTAssertEqual(WardrobeFilter(searchText: "linen").apply(to: all).map(\.id), [byName.id])
        XCTAssertEqual(WardrobeFilter(searchText: "ZARA").apply(to: all).map(\.id), [byBrand.id])
        XCTAssertEqual(WardrobeFilter(searchText: "navy").apply(to: all).map(\.id), [byColor.id])
        XCTAssertEqual(WardrobeFilter(searchText: "casual").apply(to: all).map(\.id), [byTag.id])
    }

    func testSearchIgnoresPhotoCreditTags() {
        let credited = item("Dress", tags: ["Photo credit: Jane Doe|CC BY 2.0|https://x|https://y"])
        XCTAssertTrue(WardrobeFilter(searchText: "jane").apply(to: [credited]).isEmpty)
    }

    func testBlankSearchIsIgnored() {
        XCTAssertEqual(WardrobeFilter(searchText: "   ").apply(to: [item("A")]).count, 1)
    }

    func testCategoryFilter() {
        let top = item("T"), shoes = item("S", category: "shoes")
        XCTAssertEqual(WardrobeFilter(category: .shoes).apply(to: [top, shoes]).map(\.id), [shoes.id])
    }

    func testSeasonFilterKeepsMatchingAndAllYearPieces() {
        let summer = item("S", season: "summer"), winter = item("W", season: "winter")
        let allYear = item("A", season: "all"), unset = item("U")
        let result = WardrobeFilter(season: .summer).apply(to: [summer, winter, allYear, unset])
        XCTAssertEqual(Set(result.map(\.id)), [summer.id, allYear.id])
    }

    func testSortNewestFirst() {
        let old = item("Old", created: 100), new = item("New", created: 200)
        XCTAssertEqual(WardrobeFilter(sort: .newest).apply(to: [old, new]).map(\.id), [new.id, old.id])
    }

    func testSortByNameIgnoresCaseAndPutsUnnamedLast() {
        let b = item("beta"), a = item("Alpha"), unnamed = item(nil)
        XCTAssertEqual(WardrobeFilter(sort: .name).apply(to: [unnamed, b, a]).map(\.id), [a.id, b.id, unnamed.id])
    }

    func testSortMostWornPutsFavoritesFirst() {
        let rare = item("R", frequency: "rarely"), fav = item("F", frequency: "favorite")
        let often = item("O", frequency: "often"), unset = item("U")
        XCTAssertEqual(WardrobeFilter(sort: .mostWorn).apply(to: [unset, rare, often, fav]).map(\.id),
                       [fav.id, often.id, rare.id, unset.id])
    }

    func testIsActiveReflectsNonDefaultCriteria() {
        XCTAssertFalse(WardrobeFilter().isActive)
        XCTAssertTrue(WardrobeFilter(searchText: "a").isActive)
        XCTAssertTrue(WardrobeFilter(category: .top).isActive)
        XCTAssertTrue(WardrobeFilter(season: .winter).isActive)
        XCTAssertFalse(WardrobeFilter(sort: .name).isActive)
    }
}

final class WardrobeWearTrackingTests: XCTestCase {
    private func item(worn: Int?, frequency: String? = nil) -> WardrobeItem {
        WardrobeItem(id: UUID(), ownerId: UUID(), imageUrl: "", name: nil, category: "top", subcategory: nil,
                     color: nil, season: nil, brand: nil, wearFrequency: frequency, tags: nil,
                     createdAt: nil, updatedAt: nil, wearCount: worn, lastWornAt: nil)
    }

    func testMostWornSortsByLoggedWearsBeforeFrequencyLabel() {
        let twice = item(worn: 2, frequency: "favorite"), nine = item(worn: 9, frequency: "rarely"), never = item(worn: nil, frequency: "often")
        XCTAssertEqual(WardrobeFilter(sort: .mostWorn).apply(to: [twice, never, nine]).map(\.id), [nine.id, twice.id, never.id])
    }

    func testWearSummaryText() {
        XCTAssertNil(item(worn: nil).wearSummary)
        XCTAssertNil(item(worn: 0).wearSummary)
        XCTAssertEqual(item(worn: 1).wearSummary, "Worn 1 time")
        XCTAssertEqual(item(worn: 4).wearSummary, "Worn 4 times")
    }
}
