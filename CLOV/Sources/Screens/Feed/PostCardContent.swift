import Foundation

/// Pure display rules for the feed post card, kept out of the view so they
/// can be unit tested.
enum PostCardContent {
    static let fallbackTitle = "Fit-Check"

    /// The vote prompt, else the occasion, else a generic title.
    static func title(votePrompt: String?, occasion: String?) -> String {
        for candidate in [votePrompt, occasion] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return fallbackTitle
    }

    /// Photo URLs in display order; photos with unusable URLs are dropped.
    static func photoURLs(_ photos: [FitCheckPhoto]) -> [URL] {
        photos.sorted { $0.position < $1.position }
            .compactMap { URL(string: $0.imageUrl) }
            .filter { $0.scheme?.hasPrefix("http") == true && $0.host != nil }
    }

    /// The photo the carousel shows at `index`: same order and same filtering as
    /// `photoURLs`, so a press on the visible photo votes for that photo.
    static func photo(at index: Int, in photos: [FitCheckPhoto]) -> FitCheckPhoto? {
        let shown = photos.sorted { $0.position < $1.position }.filter { photo in
            guard let url = URL(string: photo.imageUrl) else { return false }
            return url.scheme?.hasPrefix("http") == true && url.host != nil
        }
        return shown.indices.contains(index) ? shown[index] : nil
    }

    /// "@nickname" when set, else "@CODE" (the generated CLO·V ID), else "@someone".
    static func handle(accountCode: String?, nickname: String?) -> String {
        for candidate in [nickname, accountCode] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return "@\(trimmed)" }
        }
        return "@someone"
    }

    /// The photo's own description, else the post caption, else nil.
    static func overlayDescription(photoDescription: String?, caption: String?) -> String? {
        for candidate in [photoDescription, caption] {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// Up to `limit` non-blank tags, in order, shown as "#tag".
    static func displayTags(_ tags: [String]?, limit: Int = 4) -> [String] {
        (tags ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.prefix(limit).map { "#\($0)" }
    }

    /// Text shared from the Send action. With a link: "<title>\n\nVote on CLO·V: <url>";
    /// without one (share domain not configured): "<title>\n\nCheck out this Fit-Check on CLO·V".
    static func shareText(title: String, url: URL?) -> String {
        guard let url else { return "\(title)\n\nCheck out this Fit-Check on CLO·V" }
        return "\(title)\n\nVote on CLO·V: \(url.absoluteString)"
    }

    /// Like total to show next to the Like button; nil (hidden) when unknown or zero.
    static func displayLikeCount(_ count: Int?) -> Int? {
        guard let count, count > 0 else { return nil }
        return count
    }

    /// A copy of `item` that records the viewer's vote (`nil` clears it), so a card
    /// that scrolls away and is rebuilt still knows how the viewer voted. Other
    /// voters' rows are kept, and the total moves only when the vote is added or removed.
    static func applyingVote(_ photoId: UUID?, voterId: UUID, to item: FeedItemDTO) -> FeedItemDTO {
        let previous = item.ownVote(voterId: voterId)
        guard previous != photoId else { return item }
        var updated = item
        updated.fitCheckVotes = item.fitCheckVotes.filter { $0.voterId != voterId }
            + (photoId.map { [VoteRef(photoId: $0, voterId: voterId)] } ?? [])
        let change = (photoId == nil ? 0 : 1) - (previous == nil ? 0 : 1)
        updated.voteCount = item.voteCount.map { max(0, $0 + change) }
        return updated
    }

    /// Label on a card's vote button: "Look 2".
    static func voteButtonTitle(position: Int) -> String { "Look \(position)" }

    /// What VoiceOver says for that button: "Vote for Look 2".
    static func voteButtonAccessibilityLabel(position: Int) -> String { "Vote for \(voteButtonTitle(position: position))" }
}
