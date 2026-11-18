import Foundation

// Shapes for PostgREST embedded ("nested select") queries — mirrors the
// `.select("id, ..., fit_check_photos(...), profiles(...)")` queries in
// the web prototype's src/app/feed/page.tsx and src/app/vote/[id]/page.tsx.

struct VoteRef: Codable {
    let photoId: UUID
    let voterId: UUID
}

struct CommentRef: Codable {
    let id: UUID
}

struct FeedItemDTO: Codable, Identifiable {
    let id: UUID
    let creatorId: UUID
    var caption: String?
    var occasion: String?
    var audience: String?
    var votePrompt: String?
    var createdAt: Date
    var expiresAt: Date?
    var fitCheckPhotos: [FitCheckPhoto]
    var fitCheckVotes: [VoteRef]
    var fitCheckComments: [CommentRef]
    var profiles: AuthorInfo?
    /// From fit_checks.is_public. Nil when the server did not send it, which
    /// callers must treat as "not public".
    var isPublic: Bool?
    /// Post-level tags and like total; nil until migrations 20261107* are live.
    var tags: [String]? = nil
    var likeCount: Int? = nil
    /// fit_checks.vote_count (publicly readable total); nil on older rows.
    var voteCount: Int? = nil
    var visibleCommentCount: Int? = nil

    var commentCount: Int { visibleCommentCount ?? fitCheckComments.count }
}


// Feed queries deliberately omit vote rows. Keep the in-memory field for sample
// data and callers that already have a summary, while decoding an absent embed.
extension FeedItemDTO {
    private enum CodingKeys: String, CodingKey {
        case id, creatorId, caption, occasion, audience, votePrompt, createdAt, expiresAt
        case fitCheckPhotos, fitCheckVotes, fitCheckComments, profiles, isPublic, tags, likeCount, voteCount
        case visibleCommentCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        creatorId = try values.decode(UUID.self, forKey: .creatorId)
        caption = try values.decodeIfPresent(String.self, forKey: .caption)
        occasion = try values.decodeIfPresent(String.self, forKey: .occasion)
        audience = try values.decodeIfPresent(String.self, forKey: .audience)
        votePrompt = try values.decodeIfPresent(String.self, forKey: .votePrompt)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        expiresAt = try values.decodeIfPresent(Date.self, forKey: .expiresAt)
        fitCheckPhotos = try values.decode([FitCheckPhoto].self, forKey: .fitCheckPhotos)
        fitCheckVotes = try values.decodeIfPresent([VoteRef].self, forKey: .fitCheckVotes) ?? []
        fitCheckComments = try values.decodeIfPresent([CommentRef].self, forKey: .fitCheckComments) ?? []
        profiles = try values.decodeIfPresent(AuthorInfo.self, forKey: .profiles)
        isPublic = try values.decodeIfPresent(Bool.self, forKey: .isPublic)
        tags = try values.decodeIfPresent([String].self, forKey: .tags)
        likeCount = try values.decodeIfPresent(Int.self, forKey: .likeCount)
        voteCount = try values.decodeIfPresent(Int.self, forKey: .voteCount)
        visibleCommentCount = try values.decodeIfPresent(Int.self, forKey: .visibleCommentCount)
    }
}

struct FitCheckDetailDTO: Codable {
    let id: UUID
    var caption: String?
    var occasion: String?
    var audience: String?
    var votePrompt: String?
    var status: String
    let creatorId: UUID
    var expiresAt: Date?
    var fitCheckPhotos: [FitCheckPhoto]
    var profiles: AuthorInfo?
    /// From fit_checks.is_public; nil must be treated as "not public".
    var isPublic: Bool?
}

struct CommentDTO: Codable, Identifiable {
    let id: UUID
    let body: String
    var createdAt: Date
    var profiles: AuthorInfo?
    /// The photo this comment is about; nil for a general comment on the whole Fit-Check.
    var photoId: UUID? = nil
}

struct MembershipGroupDTO: Codable {
    var groups: FashionGroup?
}

struct MemberDTO: Codable {
    let profileId: UUID
    var profiles: AuthorInfo?
}

struct GroupMemberDisplay: Identifiable {
    let id: UUID
    let nickname: String?
    let avatarUrl: String?
}

struct FriendRequestDTO: Codable, Identifiable {
    let id: UUID
    let requesterId: UUID
    let addresseeId: UUID
    let status: String
}

struct FriendshipDTO: Codable {
    let userLow: UUID
    let userHigh: UUID
}

struct AuthorInfoWithId: Codable, Identifiable {
    let id: UUID
    var nickname: String?
    var accountCode: String
    var avatarUrl: String?
    var mutualCount: Int = 0

    // `mutualCount` is filled in client-side from get_mutual_friend_counts;
    // profile queries never return it, so it must not be required when decoding.
    private enum CodingKeys: String, CodingKey { case id, nickname, accountCode, avatarUrl }
}

struct MutualFriendCountDTO: Codable {
    let userId: UUID
    let mutualCount: Int
}

// `notifications` has two FKs to `profiles` (recipient_id, actor_id), so
// the embed needs disambiguating — see the `actor:profiles!...` alias
// in API.fetchNotifications, which is what makes the JSON key "actor"
// instead of the default "profiles".
struct NotificationDTO: Codable, Identifiable {
    let id: UUID
    let type: String
    var isRead: Bool
    var createdAt: Date
    let fitCheckId: UUID?
    var actor: AuthorInfo?
}
