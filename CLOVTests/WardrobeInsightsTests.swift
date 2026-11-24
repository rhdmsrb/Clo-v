import Foundation
import Testing
@testable import CLOV

@Suite("Wardrobe insights")
struct WardrobeInsightsTests {
    private func item(_ category: String, color: String? = nil, brand: String? = nil, season: String? = nil,
                      tags: [String]? = nil, wears: Int? = nil, price: Decimal? = nil) -> WardrobeItem {
        WardrobeItem(id: UUID(), ownerId: UUID(), imageUrl: "", name: nil, category: category,
                     subcategory: nil, color: color, season: season, brand: brand, wearFrequency: nil,
                     tags: tags, createdAt: nil, updatedAt: nil, wearCount: wears, lastWornAt: nil, price: price)
    }

    @Test("Category slices are counted, ranked largest first and share the whole")
    func categorySlicesRankByCount() {
        let insights = WardrobeInsights(items: [item("top"), item("top"), item("shoes")])

        let slices = insights.slices(by: .category)

        #expect(slices.map(\.label) == ["Tops", "Shoes"])
        #expect(slices.map(\.count) == [2, 1])
        #expect(abs(slices.map(\.share).reduce(0, +) - 1) < 0.0001)
    }

    @Test("Free-text colors group case- and whitespace-insensitively; blanks are Not set")
    func colorsNormalize() {
        let insights = WardrobeInsights(items: [item("top", color: "black"), item("top", color: " Black "),
                                                item("top", color: nil), item("top", color: "  ")])

        let slices = insights.slices(by: .color)

        #expect(slices == [InsightSlice(label: "Black", count: 2, share: 0.5),
                           InsightSlice(label: WardrobeInsights.unsetLabel, count: 2, share: 0.5)])
    }

    @Test("Tags count once per tag and photo credits are ignored")
    func tagsSkipPhotoCredit() {
        let insights = WardrobeInsights(items: [item("top", tags: ["Casual", "Minimal", "Photo credit: X"]),
                                                item("top", tags: ["Casual"])])

        let slices = insights.slices(by: .tag)

        #expect(slices.map(\.label) == ["Casual", "Minimal"])
        #expect(slices.map(\.count) == [2, 1])
    }

    @Test("Brands keep their typed casing")
    func brandCasingPreserved() {
        let slices = WardrobeInsights(items: [item("top", brand: "COS"), item("top", brand: "cos")]).slices(by: .brand)
        #expect(slices.map(\.label) == ["COS"])
        #expect(slices.map(\.count) == [2])
    }

    @Test("Season slices use the season label")
    func seasonLabels() {
        let slices = WardrobeInsights(items: [item("top", season: "all")]).slices(by: .season)
        #expect(slices.map(\.label) == ["All year"])
    }

    @Test("An empty wardrobe has no slices and zero value")
    func emptyWardrobe() {
        let insights = WardrobeInsights(items: [])
        #expect(insights.slices(by: .brand).isEmpty)
        #expect(insights.totalValue == 0)
        #expect(insights.averagePrice == 0)
    }

    @Test("Filtering by category keeps only that category")
    func filterByCategory() {
        let insights = WardrobeInsights(items: [item("top"), item("shoes")])
        #expect(insights.filtered(by: .shoes).items.map(\.category) == ["shoes"])
        #expect(insights.filtered(by: nil).items.count == 2)
    }

    @Test("Value and average only count priced pieces")
    func valueIgnoresUnpriced() {
        let insights = WardrobeInsights(items: [item("top", price: 30), item("top", price: 10), item("top")])

        #expect(insights.totalValue == 40)
        #expect(insights.averagePrice == 20)
        #expect(insights.pricedItemCount == 2)
    }

    @Test("Highest price and most worn rank descending; never-worn counts zero and nil")
    func rankings() {
        let cheap = item("top", wears: 5, price: 10)
        let pricey = item("shoes", wears: 1, price: 200)
        let unworn = item("bottom", wears: 0, price: 50)
        let untracked = item("bottom")
        let insights = WardrobeInsights(items: [cheap, pricey, unworn, untracked])

        #expect(insights.mostExpensive.map(\.id) == [pricey.id, unworn.id, cheap.id])
        #expect(insights.mostWorn.map(\.id) == [cheap.id, pricey.id])
        #expect(insights.neverWornCount == 2)
    }

    @Test("Cost per wear divides price by wears and ranks cheapest first")
    func costPerWear() {
        let everyday = item("top", wears: 10, price: 50)
        let rare = item("shoes", wears: 1, price: 20)
        let insights = WardrobeInsights(items: [rare, everyday, item("top", wears: 3)])

        #expect(WardrobeInsights.costPerWear(of: everyday) == 5)
        #expect(insights.bestCostPerWear.map(\.id) == [everyday.id, rare.id])
    }

    @Test("Ranked lists stop at the limit")
    func rankedListLimit() {
        let items = (1...8).map { item("top", wears: $0, price: Decimal($0)) }
        #expect(WardrobeInsights(items: items).mostExpensive.count == WardrobeInsights.rankedListLimit)
    }
}

@Suite("Price input")
struct PriceInputTests {
    @Test("Blank means no price")
    func blank() {
        #expect(PriceInput.parse("  ") == .success(nil))
    }

    @Test("Accepts dollar signs and thousands separators and rounds to cents", arguments: [
        ("49.99", Decimal(string: "49.99")!),
        ("$1,299", Decimal(1299)),
        ("12.345", Decimal(string: "12.35")!)
    ])
    func parsesValid(input: String, expected: Decimal) {
        #expect(PriceInput.parse(input) == .success(expected))
    }

    @Test("Rejects bad input with a clear reason")
    func rejectsInvalid() {
        #expect(PriceInput.parse("abc") == .failure(.notANumber))
        #expect(PriceInput.parse("-5") == .failure(.negative))
        #expect(PriceInput.parse("100000000") == .failure(.tooLarge))
    }

    @Test("Field text round-trips the stored price")
    func textRoundTrip() {
        #expect(PriceInput.text(for: Decimal(string: "12.5")) == "12.5")
        #expect(PriceInput.text(for: nil) == "")
    }

    @Test("Price edits only send the column when it changed")
    func priceChange() {
        #expect(PriceChange.from(old: 10, new: 10) == .unchanged)
        #expect(PriceChange.from(old: nil, new: 5) == .set(5))
        #expect(PriceChange.from(old: 5, new: nil) == .cleared)
    }
}
