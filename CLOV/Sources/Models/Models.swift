import Foundation

// Mirrors the Postgres schema in supabase/migrations/*.sql from the web
// prototype (../prototype). Same backend, same tables — see
// SupabaseManager.swift for the shared JSONDecoder that maps
// snake_case columns to these camelCase properties.

struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var nickname: String?
    var stylePreferences: [String]
    var avatarUrl: String?
    var createdAt: Date?

    var isOnboarded: Bool { !(nickname ?? "").isEmpty }

    init(id: UUID, nickname: String?, stylePreferences: [String], avatarUrl: String?, createdAt: Date?) {
        self.id = id
        self.nickname = nickname
        self.stylePreferences = stylePreferences
        self.avatarUrl = avatarUrl
        self.createdAt = createdAt
    }

    // Profile rows can predate optional profile columns in the deployed
    // database. Keep loading the account when those columns are absent or
    // null; otherwise a harmless schema rollout mismatch blocks the whole app.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
        stylePreferences = try container.decodeIfPresent([String].self, forKey: .stylePreferences) ?? []
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

struct ProfileFollow: Codable, Hashable {
    let followerId: UUID
    let followingId: UUID
    var createdAt: Date?
}

struct FitCheck: Codable, Identifiable {
    let id: UUID
    let creatorId: UUID
    var caption: String?
    var status: String
    var isPublic: Bool
    var groupId: UUID?
    var createdAt: Date?
    var endedAt: Date?
    /// Not in the original CLAUDE.md scope; added on request. Once this
    /// passes, voting closes AND results are fully hidden — stricter
    /// than a manually "Terminated" post, which stays read-only-visible.
    var expiresAt: Date?
}

/// `true` once `expiresAt` has passed. `false` (never expires) for
/// posts created before this feature, or with a nil `expiresAt`.
func isExpired(_ expiresAt: Date?) -> Bool {
    guard let expiresAt else { return false }
    return expiresAt <= Date()
}

struct FitCheckPhoto: Codable, Identifiable, Equatable {
    let id: UUID
    let fitCheckId: UUID?
    var imageUrl: String
    let position: Int
}

struct FitCheckVote: Codable, Identifiable {
    let id: UUID
    let fitCheckId: UUID
    let photoId: UUID
    let voterId: UUID
    var createdAt: Date?
}

struct FitCheckComment: Codable, Identifiable {
    let id: UUID
    let fitCheckId: UUID
    let photoId: UUID?
    let commenterId: UUID
    let body: String
    var createdAt: Date?
}

struct FashionGroup: Codable, Identifiable {
    let id: UUID
    var name: String
    let creatorId: UUID
    let inviteCode: String
    var createdAt: Date?
}

struct GroupMember: Codable {
    let groupId: UUID
    let profileId: UUID
    var joinedAt: Date?
}

struct WardrobeItem: Codable, Identifiable, Equatable {
    let id: UUID
    let ownerId: UUID
    var imageUrl: String
    var name: String?
    var category: String
    var subcategory: String?
    var color: String?
    var season: String?
    var brand: String?
    var wearFrequency: String?
    var tags: [String]?
    var createdAt: Date?
    var updatedAt: Date?
}

/// Lightweight activity summary shown in the account tab. The counts are
/// intentionally derived from the same rows the app already writes, so the
/// report stays useful without introducing a second analytics pipeline.
struct WeeklyStyleReport: Equatable {
    let votesCast: Int
    let fitChecksPosted: Int
    let commentsWritten: Int
    let wardrobePiecesAdded: Int
    let currentStreak: Int
    let topOccasion: String?
}

enum WardrobeCategory: String, CaseIterable, Identifiable {
    case top, bottom, dress, outerwear, shoes, accessory, set, other
    var id: Self { self }
    var label: String {
        switch self {
        case .top: "Tops"
        case .bottom: "Bottoms"
        case .dress: "Dresses"
        case .outerwear: "Outerwear"
        case .shoes: "Shoes"
        case .accessory: "Accessories"
        case .set: "Sets"
        case .other: "Other"
        }
    }
}

enum WardrobeSeason: String, CaseIterable, Identifiable {
    case spring, summer, fall, winter, all
    var id: Self { self }
    var label: String { rawValue == "all" ? "All year" : rawValue.capitalized }
}

enum WardrobeFrequency: String, CaseIterable, Identifiable {
    case rarely, sometimes, often, favorite
    var id: Self { self }
    var label: String {
        switch self {
        case .rarely: "Rarely"
        case .sometimes: "Sometimes"
        case .often: "Often"
        case .favorite: "Favorite"
        }
    }
}

// Lightweight profile info for embedding in feed/comment rows.
struct AuthorInfo: Codable {
    var nickname: String?
    var avatarUrl: String?
}

// Not in the original CLAUDE.md scope; added on request. Notifies a
// Fit-Check's creator when someone votes or comments on it.
struct AppNotification: Codable, Identifiable {
    let id: UUID
    let recipientId: UUID
    let actorId: UUID
    let type: String // "vote" | "comment"
    let fitCheckId: UUID
    let photoId: UUID?
    let commentId: UUID?
    var isRead: Bool
    var createdAt: Date?
}
