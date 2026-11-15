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
