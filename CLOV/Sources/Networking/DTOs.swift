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
}

struct CommentDTO: Codable, Identifiable {
    let id: UUID
    let body: String
    var createdAt: Date
    var profiles: AuthorInfo?
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
