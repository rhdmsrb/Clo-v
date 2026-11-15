import Foundation

extension FeedItemDTO {
    /// Total votes for ranking and display. Prefers the server-maintained
    /// `fit_checks.vote_count`; `fitCheckVotes` is only a fallback because
    /// under the restricted vote policy it holds at most the viewer's own row.
    var totalVotes: Int { voteCount ?? fitCheckVotes.count }

    /// The viewer's own vote, read from their row in the embed.
    func ownVote(voterId: UUID) -> UUID? {
        fitCheckVotes.first(where: { $0.voterId == voterId })?.photoId
    }
}

/// Share-sheet copy derived from a vote summary.
enum VoteShareText {
    static let fallback = "Help me choose my outfit on CLO·V."

    /// Falls back to the generic invite when counts are unknown or empty.
    static func make(from summary: VoteSummary?) -> String {
        guard let summary, summary.isRevealed, summary.total > 0 else { return fallback }
        let leading = summary.counts.values.max() ?? 0
        let percentage = Int((Double(leading) / Double(summary.total) * 100).rounded())
        let total = summary.total
        return "My Fit-Check is at \(percentage)% for the leading look (\(total) vote\(total == 1 ? "" : "s"))."
    }
}
