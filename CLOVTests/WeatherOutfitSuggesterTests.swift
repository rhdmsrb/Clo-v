import XCTest
@testable import CLOV

final class WeatherOutfitSuggesterTests: XCTestCase {
    private func item(_ category: String, season: String? = nil, frequency: String? = nil, worn: Int? = nil) -> WardrobeItem {
        WardrobeItem(id: UUID(), ownerId: UUID(), imageUrl: "", name: category, category: category,
                     subcategory: nil, color: nil, season: season, brand: nil, wearFrequency: frequency,
                     tags: nil, createdAt: nil, updatedAt: nil, wearCount: worn, lastWornAt: nil)
    }

    private func weather(feelsLike: Double, rainChance: Int = 0, wind: Double = 5, snow: Double = 0) -> LocalWeatherConditions {
        LocalWeatherConditions(
            temperatureC: feelsLike, feelsLikeC: feelsLike, precipitationMM: 0, rainMM: 0, showersMM: 0,
            snowfallCM: snow, weatherCode: 3, windKPH: wind, todayLowC: feelsLike - 2, todayHighC: feelsLike + 2,
            rainChancePercent: rainChance, todayMaxWindKPH: wind, todayWeatherCode: 3)
    }

    private func categories(_ items: [WardrobeItem]) -> Set<String> { Set(items.map(\.category)) }

    func testEmptyWardrobeSuggestsNothing() {
        XCTAssertTrue(WeatherOutfitSuggester.suggest(from: [], weather: weather(feelsLike: 10)).isEmpty)
    }

    func testColdDayPicksWinterOuterwearBottomAndShoes() {
        let winterTop = item("top", season: "winter"), summerTop = item("top", season: "summer")
        let bottom = item("bottom", season: "all"), coat = item("outerwear", season: "winter"), boots = item("shoes", season: "winter")
        let result = WeatherOutfitSuggester.suggest(from: [summerTop, winterTop, bottom, coat, boots], weather: weather(feelsLike: 2))
        // Outerwear takes the upper-body slot, matching the planner's selection rules.
        XCTAssertEqual(Set(result.map(\.id)), [bottom.id, coat.id, boots.id])
        XCTAssertFalse(result.contains { $0.id == winterTop.id || $0.id == summerTop.id })
    }

    func testHotDayDoesNotSuggestOuterwear() {
        let result = WeatherOutfitSuggester.suggest(
            from: [item("top", season: "summer"), item("bottom", season: "summer"), item("outerwear", season: "all")],
            weather: weather(feelsLike: 30))
        XCTAssertFalse(categories(result).contains("outerwear"))
    }

    func testHotDayPrefersSummerDressOverMismatchedSeparates() {
        let dress = item("dress", season: "summer")
        let result = WeatherOutfitSuggester.suggest(from: [dress, item("top", season: "winter"), item("bottom", season: "winter")],
                                                    weather: weather(feelsLike: 31))
        XCTAssertEqual(result.map(\.id), [dress.id])
    }

    func testRainOnMildDayAddsOuterwear() {
        let jacket = item("outerwear", season: "all")
        let result = WeatherOutfitSuggester.suggest(from: [item("top", season: "all"), item("bottom", season: "all"), jacket],
                                                    weather: weather(feelsLike: 19, rainChance: 70))
        XCTAssertTrue(result.contains { $0.id == jacket.id })
    }

    func testSeasonMismatchedPiecesAreLeftOut() {
        let result = WeatherOutfitSuggester.suggest(from: [item("top", season: "summer")], weather: weather(feelsLike: 0))
        XCTAssertTrue(result.isEmpty)
    }

    func testFavoriteBeatsRarelyWornWhenSeasonsTie() {
        let favorite = item("top", season: "all", frequency: "favorite"), rare = item("top", season: "all", frequency: "rarely")
        let result = WeatherOutfitSuggester.suggest(from: [rare, favorite], weather: weather(feelsLike: 18))
        XCTAssertEqual(result.map(\.id), [favorite.id])
    }

    func testAccessoriesAndOtherAreNeverSuggested() {
        let result = WeatherOutfitSuggester.suggest(from: [item("accessory", season: "all"), item("other", season: "all")],
                                                    weather: weather(feelsLike: 18))
        XCTAssertTrue(result.isEmpty)
    }

    func testSuggestionNeverContainsConflictingPieces() {
        let items = [item("dress", season: "all"), item("top", season: "all"), item("bottom", season: "all"), item("outerwear", season: "all")]
        let result = WeatherOutfitSuggester.suggest(from: items, weather: weather(feelsLike: 10))
        let ids = Set(result.map(\.id))
        var selected = Set<UUID>()
        for piece in result { selected = OutfitSelection.toggling(piece, selected: selected, in: items) }
        XCTAssertEqual(selected, ids)
    }
}
