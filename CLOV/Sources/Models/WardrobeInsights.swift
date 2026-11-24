import Foundation

/// The attribute the insights donut groups wardrobe pieces by.
enum InsightDimension: String, CaseIterable, Identifiable {
    case category, color, brand, season, tag
    var id: Self { self }

    var label: String {
        switch self {
        case .category: "Category"
        case .color: "Color"
        case .brand: "Brand"
        case .season: "Season"
        case .tag: "Tag"
        }
    }

    /// Lowercased plural noun for the chart's centre caption ("in 3 colors").
    func countNoun(_ count: Int) -> String {
        let singular: String = switch self {
        case .category: "category"
        case .color: "color"
        case .brand: "brand"
        case .season: "season"
        case .tag: "tag"
        }
        guard count != 1 else { return singular }
        return self == .category ? "categories" : singular + "s"
    }
}

/// One wedge of the donut: a group label, how many pieces fall in it and its
/// share of the filtered wardrobe.
struct InsightSlice: Equatable, Identifiable {
    let label: String
    let count: Int
    let share: Double
    var id: String { label }
}

/// Pure summaries of a wardrobe for the Wardrobe insights screen. Nothing here
/// touches the network, so every number on that screen is unit-testable.
struct WardrobeInsights: Equatable {
    static let unsetLabel = "Not set"
    static let rankedListLimit = 5

    let items: [WardrobeItem]

    /// Pieces in `category`, or every piece when `category` is nil.
    func filtered(by category: WardrobeCategory?) -> WardrobeInsights {
        guard let category else { return self }
        return WardrobeInsights(items: items.filter { $0.category == category.rawValue })
    }

    /// Groups pieces by `dimension`, largest first, ties broken alphabetically.
    /// A piece with several tags counts once per tag; with no value it falls
    /// under "Not set" so the shares still add up to the whole wardrobe.
    func slices(by dimension: InsightDimension) -> [InsightSlice] {
        // Group case-insensitively ("black" and "Black"), but show the first
        // spelling seen so brands like "COS" keep their casing.
        var displayLabels: [String: String] = [:]
        let keyedCounts = items.reduce(into: [String: Int]()) { counts, item in
            for label in Self.labels(for: item, dimension: dimension) {
                let key = label.lowercased()
                if displayLabels[key] == nil { displayLabels[key] = label }
                counts[key, default: 0] += 1
            }
        }
        let counts = Dictionary(uniqueKeysWithValues: keyedCounts.map { (displayLabels[$0.key] ?? $0.key, $0.value) })
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }
        let slices: [InsightSlice] = counts.map { label, count in
            InsightSlice(label: label, count: count, share: Double(count) / Double(total))
        }
        return slices.sorted(by: Self.isRankedBefore)
    }

    /// Sum of every priced piece.
    var totalValue: Decimal {
        pricedItems.reduce(Decimal.zero) { $0 + ($1.price ?? 0) }
    }

    /// Mean price of the pieces that have one; zero when none do.
    var averagePrice: Decimal {
        let priced = pricedItems
        guard !priced.isEmpty else { return 0 }
        return totalValue / Decimal(priced.count)
    }

    var pricedItemCount: Int { pricedItems.count }

    var mostExpensive: [WardrobeItem] {
        Array(pricedItems.sorted { ($0.price ?? 0) > ($1.price ?? 0) }.prefix(Self.rankedListLimit))
    }

    var mostWorn: [WardrobeItem] {
        Array(items.filter { ($0.wearCount ?? 0) > 0 }
            .sorted { ($0.wearCount ?? 0) > ($1.wearCount ?? 0) }
            .prefix(Self.rankedListLimit))
    }

    var neverWornCount: Int { items.filter { ($0.wearCount ?? 0) == 0 }.count }

    /// Priced, worn pieces ordered by lowest price per wear first.
    var bestCostPerWear: [WardrobeItem] {
        Array(items.filter { Self.costPerWear(of: $0) != nil }
            .sorted { (Self.costPerWear(of: $0) ?? 0) < (Self.costPerWear(of: $1) ?? 0) }
            .prefix(Self.rankedListLimit))
    }

    static func costPerWear(of item: WardrobeItem) -> Decimal? {
        guard let price = item.price, let wears = item.wearCount, wears > 0 else { return nil }
        return price / Decimal(wears)
    }

    private static func isRankedBefore(_ lhs: InsightSlice, _ rhs: InsightSlice) -> Bool {
        lhs.count == rhs.count ? lhs.label < rhs.label : lhs.count > rhs.count
    }

    private var pricedItems: [WardrobeItem] { items.filter { $0.price != nil } }

    private static func labels(for item: WardrobeItem, dimension: InsightDimension) -> [String] {
        switch dimension {
        case .category:
            return [WardrobeCategory(rawValue: item.category)?.label ?? item.category.capitalized]
        case .color:
            return [normalized(item.color)]
        case .brand:
            return [normalized(item.brand)]
        case .season:
            return [item.season.flatMap(WardrobeSeason.init(rawValue:))?.label ?? unsetLabel]
        case .tag:
            let tags = (item.tags ?? []).filter { !$0.hasPrefix("Photo credit:") }
            let unique = Dictionary(tags.map { (normalized($0).lowercased(), normalized($0)) }) { first, _ in first }
            return tags.isEmpty ? [unsetLabel] : Array(unique.values)
        }
    }

    /// Trims free text and capitalises only its first letter, so "black"
    /// reads "Black" while "COS" and "Levi's" stay as typed.
    private static func normalized(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let first = trimmed.first else { return unsetLabel }
        return first.uppercased() + trimmed.dropFirst()
    }
}
