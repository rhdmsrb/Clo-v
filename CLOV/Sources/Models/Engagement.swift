import Foundation

/// One row of `get_live_vote_tally`: the live vote total for a single photo.
/// The RPC returns no rows unless the caller is the post's creator or has voted.
struct LivePhotoTally: Codable, Equatable {
    let photoId: UUID
    let voteCount: Int
    let isMine: Bool
}

/// Post ids the current user has liked / saved, with the server-side count.
struct EngagementState: Equatable {
    var isLiked: Bool
    var isBookmarked: Bool
    var likeCount: Int
}

/// What the viewer is allowed to see about a post's votes.
struct VoteSummary: Equatable {
    let counts: [UUID: Int]
    let total: Int
    let myVote: UUID?
    let isRevealed: Bool

    /// Nothing revealed: the viewer has not voted and is not the creator.
    static func hidden(myVote: UUID?) -> VoteSummary {
        VoteSummary(counts: [:], total: 0, myVote: myVote, isRevealed: false)
    }

    /// Builds a revealed summary from RPC rows. `myVote` wins when supplied;
    /// otherwise it comes from the tally's `isMine` row.
    static func from(tally: [LivePhotoTally], myVote: UUID?) -> VoteSummary {
        let counts = Dictionary(tally.map { ($0.photoId, $0.voteCount) },
                                uniquingKeysWith: +)
        return VoteSummary(counts: counts,
                           total: counts.values.reduce(0, +),
                           myVote: myVote ?? tally.first(where: \.isMine)?.photoId,
                           isRevealed: true)
    }

    /// Legacy path: derive a revealed summary from raw vote rows.
    static func from(votes: [VoteRef], voterId: UUID, myVote: UUID?) -> VoteSummary {
        let counts = Dictionary(votes.map { ($0.photoId, 1) }, uniquingKeysWith: +)
        return VoteSummary(counts: counts,
                           total: votes.count,
                           myVote: myVote ?? votes.first(where: { $0.voterId == voterId })?.photoId,
                           isRevealed: true)
    }
}
