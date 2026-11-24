import Foundation

/// The Home filter chips (Popular · New · Following · the viewer's styles) and how
/// each one narrows or reorders the already-ranked feed. Pure, so it is unit tested;
/// filtering runs over loaded posts only and never changes what is fetched.
enum HomeFeedFilters {
    static let popular = "popular"
    static let new = "new"
    static let following = "following"
    private static let tagPrefix = "tag:"

    static func options(stylePreferences: [String]) -> [FilterOption] {
        var seen = Set<String>()
        let styles = stylePreferences.compactMap { style -> FilterOption? in
            let title = style.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = title.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return FilterOption(id: tagPrefix + key, title: title)
        }
        return [
            FilterOption(id: popular, title: "Popular"),
            FilterOption(id: new, title: "New"),
            FilterOption(id: following, title: "Following")
        ] + styles
    }

    /// `ranked` is the feed in its Popular order.
    static func apply(_ filterID: String, to ranked: [FeedItemDTO], followingIDs: Set<UUID>) -> [FeedItemDTO] {
        switch filterID {
        case new:
            return ranked.sorted { $0.createdAt > $1.createdAt }
        case following:
            return ranked.filter { followingIDs.contains($0.creatorId) }
        case let id where id.hasPrefix(tagPrefix):
            let tag = String(id.dropFirst(tagPrefix.count))
            return ranked.filter { matches($0, tag: tag) }
        default:
            return ranked
        }
    }

    private static func matches(_ item: FeedItemDTO, tag: String) -> Bool {
        let tags = (item.tags ?? []).map(normalized)
        if tags.contains(tag) { return true }
        return (item.occasion ?? "").lowercased().contains(tag)
    }

    private static func normalized(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
    }
}
