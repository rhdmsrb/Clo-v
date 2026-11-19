import Foundation

/// When and how the feed asks the viewer to bring friends in. A Fit-Check only
/// works if people vote on it, so a thin feed is the moment to invite.
enum FeedInvite {
    /// Below this many posts the feed ends with an invite card.
    static let sparseFeedThreshold = 5

    static func shouldShow(postCount: Int, hasLoaded: Bool) -> Bool {
        hasLoaded && postCount < sparseFeedThreshold
    }

    /// Shared text: names the viewer's CLO·V ID when known, so friends can add them straight away.
    static func message(accountCode: String?) -> String {
        let base = "Help me pick my outfit on CLO·V!"
        let code = accountCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return code.isEmpty ? base : "\(base) Add me with my ID: \(code)"
    }
}
