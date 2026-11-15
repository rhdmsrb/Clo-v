import Foundation

enum ExploreSort: String, CaseIterable, Identifiable {
    case newest, mostVoted

    var id: String { rawValue }
    var title: String { self == .newest ? "Newest" : "Most voted" }
}

/// Filter state edited in the Explore Filters sheet.
struct ExploreFilter: Equatable {
    static let occasions = ["Everyday", "Work", "Date", "Interview", "Party", "Travel", "Wedding"]

    var occasion: String?
    var sort: ExploreSort = .newest
    /// Keeps only posts carrying this tag (matched case-insensitively).
    var tag: String?

    var isDefault: Bool { self == ExploreFilter() }
    var activeCount: Int { (occasion == nil ? 0 : 1) + (sort == .newest ? 0 : 1) + (tag == nil ? 0 : 1) }

    /// Distinct tags across `items`, sorted, for the filter sheet's choices.
    static func availableTags(in items: [FeedItemDTO]) -> [String] {
        Array(Set(items.flatMap { $0.tags ?? [] }.map { $0.lowercased() })).sorted()
    }

    /// Ordering for already-fetched results. Newest is the server order
    /// (created_at descending), re-asserted so the result is deterministic.
    func apply(to items: [FeedItemDTO]) -> [FeedItemDTO] {
        let tagged = tag.map { wanted in
            items.filter { ($0.tags ?? []).contains { $0.lowercased() == wanted.lowercased() } }
        } ?? items
        switch sort {
        case .newest: return tagged.sorted { $0.createdAt > $1.createdAt }
        case .mostVoted:
            return tagged.sorted {
                $0.fitCheckVotes.count != $1.fitCheckVotes.count
                    ? $0.fitCheckVotes.count > $1.fitCheckVotes.count
                    : $0.createdAt > $1.createdAt
            }
        }
    }
}

/// Deterministic, varied tile aspect ratios (width / height) so the Explore
/// masonry looks staggered; the API sends no real photo dimensions.
enum ExploreTileRatio {
    static let ratios: [CGFloat] = [0.8, 1.0, 0.7, 0.9, 0.75, 1.1, 0.65, 0.85]

    static func ratio(forIndex index: Int) -> CGFloat {
        ratios[((index % ratios.count) + ratios.count) % ratios.count]
    }
}
