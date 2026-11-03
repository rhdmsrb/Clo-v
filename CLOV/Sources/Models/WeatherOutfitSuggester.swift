import Foundation

/// Picks pieces from the user's own wardrobe that suit today's weather.
enum WeatherOutfitSuggester {
    private static let coolCeilingC = 14.0
    private static let coldCeilingC = 5.0
    private static let mildCeilingC = 22.0
    private static let windyKPH = 28.0

    private static let wearRank = ["favorite": 3, "often": 2, "sometimes": 1, "rarely": 0]

    static func suggest(from items: [WardrobeItem], weather: LocalWeatherConditions) -> [WardrobeItem] {
        let feelsLike = weather.feelsLikeTemperatureC
        let candidates = items.filter { score($0, weather: weather) != nil }
        func best(_ category: String) -> WardrobeItem? { pick(category, from: candidates, weather: weather) }

        var outfit: [WardrobeItem] = []
        let top = best("top"), bottom = best("bottom")
        let onePiece = best("dress") ?? best("set")
        let preferOnePiece = feelsLike > mildCeilingC && onePiece != nil
        if let onePiece, preferOnePiece || top == nil || bottom == nil {
            outfit.append(onePiece)
        } else {
            outfit += [top, bottom].compactMap { $0 }
        }
        // The planner treats a top and outerwear as sharing the upper-body slot
        // (see OutfitSelection), so the outer layer replaces the top.
        if needsOuterLayer(weather), let layer = best("outerwear") {
            outfit = outfit.filter { !OutfitSelection.conflictingCategories(for: layer.category).contains($0.category) } + [layer]
        }
        if let shoes = best("shoes") { outfit.append(shoes) }
        return outfit
    }

    private static func needsOuterLayer(_ weather: LocalWeatherConditions) -> Bool {
        weather.feelsLikeTemperatureC <= coolCeilingC
            || weather.isWet || weather.isSnowy
            || weather.todayMaxWindKPH >= windyKPH
    }

    private static func pick(_ category: String, from items: [WardrobeItem], weather: LocalWeatherConditions) -> WardrobeItem? {
        items.filter { $0.category == category }.max { lhs, rhs in
            let l = (score(lhs, weather: weather) ?? 0, wear(lhs)), r = (score(rhs, weather: weather) ?? 0, wear(rhs))
            if l != r { return l < r }
            return lhs.id.uuidString > rhs.id.uuidString  // stable tie-break
        }
    }

    private static func wear(_ item: WardrobeItem) -> Int { item.wearFrequency.flatMap { wearRank[$0] } ?? -1 }

    /// Higher is a better seasonal fit; nil means the piece suits the weather badly.
    private static func score(_ item: WardrobeItem, weather: LocalWeatherConditions) -> Int? {
        let (primary, secondary) = seasons(for: weather)
        guard let season = item.season.flatMap(WardrobeSeason.init(rawValue:)) else { return 0 }
        if season == .all { return 2 }
        if primary.contains(season) { return 3 }
        if secondary.contains(season) { return 1 }
        return nil
    }

    private static func seasons(for weather: LocalWeatherConditions) -> (primary: Set<WardrobeSeason>, secondary: Set<WardrobeSeason>) {
        let feelsLike = weather.feelsLikeTemperatureC
        if weather.isSnowy || feelsLike <= coldCeilingC { return ([.winter], [.fall]) }
        if feelsLike <= coolCeilingC { return ([.fall], [.winter, .spring]) }
        if feelsLike <= mildCeilingC { return ([.spring, .fall], [.summer]) }
        return ([.summer], [.spring])
    }
}
