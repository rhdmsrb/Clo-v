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
