import Foundation
import UIKit
import Supabase

extension API {
    // MARK: - Groups

    static func fetchMyGroups(profileId: UUID) async throws -> [FashionGroup] {
        let rows: [MembershipGroupDTO] = try await client
            .from("group_members")
            .select("groups(id, name, creator_id, invite_code, created_at)")
            .eq("profile_id", value: profileId)
            .execute()
            .value
        return rows.compactMap(\.groups)
    }

    static func fetchGroupMembers(groupId: UUID) async throws -> [GroupMemberDisplay] {
        let rows: [MemberDTO] = try await client
            .from("group_members")
            .select("profile_id, profiles(nickname, avatar_url)")
            .eq("group_id", value: groupId)
            .execute()
            .value
        return rows.map { row in
            GroupMemberDisplay(id: row.profileId, nickname: row.profiles?.nickname, avatarUrl: row.profiles?.avatarUrl)
        }
    }

    static func isMember(groupId: UUID, profileId: UUID) async throws -> Bool {
        let rows: [GroupMember] = try await client
            .from("group_members")
            .select()
            .eq("group_id", value: groupId)
            .eq("profile_id", value: profileId)
            .execute()
            .value
        return !rows.isEmpty
    }

    static func createGroup(name: String, creatorId: UUID) async throws -> FashionGroup {
        var lastError: Error?
        for _ in 0..<3 {
            do {
                let group: FashionGroup = try await client
                    .rpc("create_group_with_owner", params: ["p_name": name, "p_code": InviteCode.generate()])
                    .single()
                    .execute()
                    .value
                return group
            } catch {
                if error.isUniqueViolation {
                    lastError = error
                    continue // invite_code collision, retry with a new code
                }
                throw error
            }
        }
        throw lastError ?? APIError.message("Couldn't create the group — try again.")
    }

    static func joinGroup(code: String) async throws -> FashionGroup {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { throw APIError.message("Enter an invite code.") }

        // `groups` is no longer readable to non-members (see
        // 0011_group_privacy.sql), so the lookup + membership insert
        // happen server-side in one SECURITY DEFINER call. The function
        // is idempotent (on conflict do nothing) and returns an empty
        // set for an unknown code.
        let groups: [FashionGroup] = try await client
            .rpc("join_group_by_code", params: ["p_code": normalized])
            .execute()
            .value
        guard let group = groups.first else {
            throw APIError.message("That code doesn't match any group.")
        }
        return group
    }

    static func renameGroup(id: UUID, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.message("Enter a board name.") }
        try await client.from("groups").update(["name": trimmed]).eq("id", value: id).execute()
    }

    static func leaveGroup(id: UUID, profileId: UUID) async throws {
        try await client.from("group_members").delete()
            .eq("group_id", value: id).eq("profile_id", value: profileId).execute()
    }

    static func deleteGroup(id: UUID) async throws {
        try await client.from("groups").delete().eq("id", value: id).execute()
    }

    static func removeGroupMember(groupId: UUID, profileId: UUID) async throws {
        try await client.from("group_members").delete()
            .eq("group_id", value: groupId).eq("profile_id", value: profileId).execute()
    }
}
