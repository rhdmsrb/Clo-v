import Foundation
import UIKit
import Supabase

extension API {
    // MARK: - Groups

    struct GroupCardPreview {
        let memberCount: Int
        let liveCount: Int
        let members: [GroupMemberDisplay]
        let thumbnails: [URL]
    }

    private struct GroupCardRow: Decodable {
        let groupId: UUID
        let memberCount: Int
        let liveCount: Int
        let members: [MemberDTO]
        let photoPaths: [String]
    }

    static func fetchGroupCardPreviews(groupIDs: [UUID]) async throws -> [UUID: GroupCardPreview]? {
        guard !groupIDs.isEmpty else { return [:] }
#if DEBUG
        if SampleData.isActive {
            return Dictionary(uniqueKeysWithValues: groupIDs.map { id in
                let members = SampleData.members(groupId: id)
                let posts = SampleData.groupFeed(groupId: id)
                return (id, GroupCardPreview(memberCount: members.count, liveCount: posts.count,
                    members: Array(members.prefix(4)),
                    thumbnails: posts.prefix(3).compactMap { PostCardContent.photoURLs($0.fitCheckPhotos).first }))
            })
        }
#endif
        let interval = Log.performance.beginInterval("Group card previews", id: Log.performance.makeSignpostID())
        defer { Log.performance.endInterval("Group card previews", interval) }
        let availability = RuntimeReadAvailability.shared
        guard await availability.shouldTry(.groupPreviews) else { return nil }
        var rows: [GroupCardRow] = []
        do {
            for start in stride(from: 0, to: groupIDs.count, by: 32) {
                try Task.checkCancellation()
                let batch = Array(groupIDs[start..<min(start + 32, groupIDs.count)])
                let result: [GroupCardRow] = try await client.rpc("group_card_previews_v1",
                    params: ["p_group_ids": batch]).execute().value
                rows.append(contentsOf: result)
            }
        } catch where isMissingColumnError(error) {
            await availability.markUnavailable(.groupPreviews)
            return nil
        }
        let urls = try await signedPhotoURLs(rows.flatMap(\.photoPaths), requireBatchSuccess: true)
        return Dictionary(uniqueKeysWithValues: rows.map { row in
            (row.groupId, GroupCardPreview(memberCount: row.memberCount, liveCount: row.liveCount,
                members: row.members.map(groupMemberDisplay),
                thumbnails: row.photoPaths.compactMap { urls[$0].flatMap { URL(string: $0) } }))
        })
    }

    /// Bounded preview for deployments awaiting the new batch RPC.
    static func fetchLegacyGroupCardPreview(groupId: UUID, blockedAuthors: Set<UUID>) async throws -> GroupCardPreview {
        struct PreviewPost: Decodable {
            struct Photo: Decodable { let imageUrl: String }
            let fitCheckPhotos: [Photo]
        }
        async let members: PostgrestResponse<[MemberDTO]> = client.from("group_members")
            .select("profile_id, profiles(nickname, avatar_url)", count: .exact)
            .eq("group_id", value: groupId).order("profile_id").limit(4).execute()
        let query = client.from("fit_checks").select("id, fit_check_photos(image_url)", count: .exact)
            .eq("group_id", value: groupId).eq("status", value: "live").or(notExpiredFilter)
        if !blockedAuthors.isEmpty {
            _ = query.not("creator_id", operator: .in, value: "(\(blockedAuthors.map(\.uuidString).joined(separator: ",")))")
        }
        let posts: PostgrestResponse<[PreviewPost]> = try await query
            .order("created_at", ascending: false).order("id", ascending: false)
            .order("position", referencedTable: "fit_check_photos").order("id", referencedTable: "fit_check_photos")
            .limit(3).limit(1, referencedTable: "fit_check_photos").execute()
        let memberPage = try await members
        let paths = posts.value.compactMap { $0.fitCheckPhotos.first?.imageUrl }
        let urls = try await signedPhotoURLs(paths)
        return GroupCardPreview(memberCount: memberPage.count ?? memberPage.value.count,
            liveCount: posts.count ?? posts.value.count, members: memberPage.value.map(groupMemberDisplay),
            thumbnails: paths.compactMap { urls[$0].flatMap { URL(string: $0) } })
    }

    private static func groupMemberDisplay(_ row: MemberDTO) -> GroupMemberDisplay {
        GroupMemberDisplay(id: row.profileId, nickname: row.profiles?.nickname, avatarUrl: row.profiles?.avatarUrl)
    }

    static func fetchMyGroups(profileId: UUID) async throws -> [FashionGroup] {
#if DEBUG
        if SampleData.isActive { return SampleData.groups }
#endif
        let rows: [MembershipGroupDTO] = try await client
            .from("group_members")
            .select("groups(id, name, creator_id, invite_code, created_at)")
            .eq("profile_id", value: profileId)
            .execute()
            .value
        return rows.compactMap(\.groups)
    }

    static func fetchGroupMembers(groupId: UUID) async throws -> [GroupMemberDisplay] {
#if DEBUG
        if SampleData.isActive { return SampleData.members(groupId: groupId) }
#endif
        let rows: [MemberDTO] = try await client
            .from("group_members")
            .select("profile_id, profiles(nickname, avatar_url)")
            .eq("group_id", value: groupId)
            .execute()
            .value
        return rows.map(groupMemberDisplay)
    }

    static func isMember(groupId: UUID, profileId: UUID) async throws -> Bool {
#if DEBUG
        if SampleData.isActive { return SampleData.group(id: groupId) != nil }
#endif
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
#if DEBUG
        if SampleData.isActive { return SampleData.createdGroup(name: name) }
#endif
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
#if DEBUG
        if SampleData.isActive { return SampleData.groups[0] }
#endif
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
#if DEBUG
        if SampleData.isActive { return }
#endif
        let trimmed = try GroupNameValidator.validated(name)
        try await client.from("groups").update(["name": trimmed]).eq("id", value: id).execute()
    }

    static func leaveGroup(id: UUID, profileId: UUID) async throws {
#if DEBUG
        if SampleData.isActive { return }
#endif
        try await client.from("group_members").delete()
            .eq("group_id", value: id).eq("profile_id", value: profileId).execute()
    }

    static func deleteGroup(id: UUID) async throws {
#if DEBUG
        if SampleData.isActive { return }
#endif
        try await client.from("groups").delete().eq("id", value: id).execute()
    }

    static func removeGroupMember(groupId: UUID, profileId: UUID) async throws {
#if DEBUG
        if SampleData.isActive { return }
#endif
        try await client.from("group_members").delete()
            .eq("group_id", value: groupId).eq("profile_id", value: profileId).execute()
    }
}
