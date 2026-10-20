import Foundation

enum FeedSortOption: Equatable {
    case forYou, newest, votes

    var title: String {
        switch self {
        case .forYou: "For you"
        case .newest: "Newest"
        case .votes: "Top voted"
        }
    }
}

enum FeedMode: Equatable { case forYou, following }

/// Pure filtering and ordering for the feed, kept out of the view so it is
/// computed once per input change rather than once per rendered row.
enum FeedRanking {
    private static let preferenceMatchScore = 3
    private static let voteScoreCap = 20
    private static let recencyWindow: TimeInterval = 86_400
    private static let recencyScore = 2

    static func visibleItems(
        items: [FeedItemDTO],
        searchText: String,
        occasion: String?,
        mode: FeedMode,
        sort: FeedSortOption,
        stylePreferences: [String],
        signalScores: [UUID: Int],
        now: Date = Date()
    ) -> [FeedItemDTO] {
        let filtered = filter(items, searchText: searchText, occasion: occasion)
        if mode == .following { return filtered.sorted { $0.createdAt > $1.createdAt } }
        switch sort {
        case .forYou:
            let preferences = Set(stylePreferences.map { $0.lowercased() })
            let scored = filtered.map { ($0, score($0, preferences: preferences, signalScores: signalScores, now: now)) }
            return scored.sorted { $0.1 > $1.1 }.map(\.0)
        case .newest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .votes:
            return filtered.sorted { $0.fitCheckVotes.count > $1.fitCheckVotes.count }
        }
    }

    private static func filter(_ items: [FeedItemDTO], searchText: String, occasion: String?) -> [FeedItemDTO] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            guard occasion == nil || item.occasion == occasion else { return false }
            guard !query.isEmpty else { return true }
            return [item.caption, item.occasion, item.profiles?.nickname]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        }
    }

    static func score(_ item: FeedItemDTO, preferences: Set<String>, signalScores: [UUID: Int], now: Date) -> Int {
        let text = [item.caption, item.occasion, item.profiles?.nickname]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let preferenceMatches = preferences.reduce(0) { $0 + (text.contains($1) ? preferenceMatchScore : 0) }
        let recency = item.createdAt > now.addingTimeInterval(-recencyWindow) ? recencyScore : 0
        return preferenceMatches + min(item.fitCheckVotes.count, voteScoreCap) + recency + (signalScores[item.id] ?? 0)
    }
}
