import Foundation
import Supabase

/// A person the signed-in user has blocked, with just what the list needs.
struct BlockedUser: Identifiable, Equatable, Sendable {
    let id: UUID
    let nickname: String?
    let avatarUrl: String?
    let blockedAt: Date?

    /// Shown when the profile can't be loaded.
    var displayName: String { nickname ?? "Unknown user" }
}

extension API {
    /// People the signed-in user has blocked, most recently blocked first.
    /// RLS limits `blocked_users` to the caller's own rows.
    static func fetchBlockedUsers() async throws -> [BlockedUser] {
#if DEBUG
        if SampleData.isActive { return sampleBlockedUsers }
#endif
        struct Row: Decodable {
            let blockedId: UUID
            let createdAt: Date?
        }
        let rows: [Row] = try await client
            .from("blocked_users")
            .select("blocked_id, created_at")
            .order("created_at", ascending: false)
            .execute()
            .value
        guard !rows.isEmpty else { return [] }
        let profiles = try await fetchProfiles(ids: rows.map(\.blockedId))
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        return rows.map { row in
            let profile = profilesByID[row.blockedId]
            return BlockedUser(id: row.blockedId, nickname: profile?.nickname, avatarUrl: profile?.avatarUrl, blockedAt: row.createdAt)
        }
    }

    /// Lifts a block. Goes through the `unblock_user` RPC because the table
    /// itself grants clients no DELETE.
    static func unblockUser(id: UUID) async throws {
#if DEBUG
        if SampleData.isActive { return }
#endif
        try await client.rpc("unblock_user", params: ["p_blocked_id": id]).execute()
    }

#if DEBUG
    private static var sampleBlockedUsers: [BlockedUser] {
        [
            BlockedUser(id: SampleData.uuid(9_001), nickname: "trend.chaser", avatarUrl: nil, blockedAt: Date().addingTimeInterval(-3 * 86_400)),
            BlockedUser(id: SampleData.uuid(9_002), nickname: "fit.critic", avatarUrl: nil, blockedAt: Date().addingTimeInterval(-40 * 86_400))
        ]
    }
#endif
}
