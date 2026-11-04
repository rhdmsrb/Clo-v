import Foundation

enum WardrobeSort: String, CaseIterable, Identifiable {
    case newest, name, mostWorn
    var id: Self { self }
    var label: String {
        switch self {
        case .newest: "Newest"
        case .name: "Name"
        case .mostWorn: "Most worn"
        }
    }
}

/// Search, category, season and sort criteria for the wardrobe grid.
struct WardrobeFilter: Equatable {
    var searchText = ""
    var category: WardrobeCategory?
    var season: WardrobeSeason?
    var sort: WardrobeSort = .newest

    private static let creditTagPrefix = "Photo credit:"
    private static let wearRank = ["favorite": 3, "often": 2, "sometimes": 1, "rarely": 0]

    /// True when search, category or season narrow the list (sort alone doesn't).
    var isActive: Bool {
        !trimmedSearch.isEmpty || category != nil || season != nil
    }

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    func apply(to items: [WardrobeItem]) -> [WardrobeItem] {
        sorted(items.filter(matches))
    }

    private func matches(_ item: WardrobeItem) -> Bool {
        if let category, item.category != category.rawValue { return false }
        if let season, item.season != season.rawValue, item.season != WardrobeSeason.all.rawValue { return false }
        let term = trimmedSearch
        guard !term.isEmpty else { return true }
        let tags = (item.tags ?? []).filter { !$0.hasPrefix(Self.creditTagPrefix) }
        let haystack = [item.name, item.subcategory, item.brand, item.color] + tags.map(Optional.some)
        return haystack.contains { $0?.localizedCaseInsensitiveContains(term) == true }
    }

    private func sorted(_ items: [WardrobeItem]) -> [WardrobeItem] {
        switch sort {
        case .newest:
            return items.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .name:
            return items.sorted { lhs, rhs in
                switch (Self.trimmedName(lhs), Self.trimmedName(rhs)) {
                case let (l?, r?): return l.localizedCaseInsensitiveCompare(r) == .orderedAscending
                case (_?, nil): return true
                default: return false
                }
            }
        case .mostWorn:
            return items.sorted { (Self.wears($0), Self.rank($0)) > (Self.wears($1), Self.rank($1)) }
        }
    }

    private static func trimmedName(_ item: WardrobeItem) -> String? {
        let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }

    private static func wears(_ item: WardrobeItem) -> Int { item.wearCount ?? 0 }

    private static func rank(_ item: WardrobeItem) -> Int {
        item.wearFrequency.flatMap { wearRank[$0] } ?? -1
    }
}
