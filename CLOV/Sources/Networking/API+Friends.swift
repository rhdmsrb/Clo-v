import Foundation
import UIKit
import Supabase

extension API {
    // MARK: - Friends

    static func fetchFriendRequests(userId: UUID, incoming: Bool) async throws -> [FriendRequestDTO] {
        let column = incoming ? "addressee_id" : "requester_id"
        return try await client.from("friend_requests").select()
            .eq(column, value: userId).eq("status", value: "pending")
            .order("created_at", ascending: false).execute().value
    }

    static func fetchFriendships(userId: UUID) async throws -> [FriendshipDTO] {
        try await client.from("friendships").select()
            .or("user_low.eq.\(userId.uuidString),user_high.eq.\(userId.uuidString)")
            .order("created_at", ascending: false).execute().value
    }

    static func searchProfiles(query: String, excluding userId: UUID) async throws -> [AuthorInfoWithId] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        if trimmed.contains("@") || digits.count >= 7 {
            return try await client.rpc("find_profiles_by_contact", params: ["p_contact": trimmed]).execute().value
        }
        let term = SearchTerm.sanitized(trimmed)
        guard !term.isEmpty else { return [] }
        return try await client.from("profiles").select("id, nickname, account_code, avatar_url")
            .or("nickname.ilike.%\(term)%,account_code.ilike.%\(term)%")
            .neq("id", value: userId).limit(20).execute().value
    }

    static func fetchProfiles(ids: [UUID]) async throws -> [AuthorInfoWithId] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("profiles").select("id, nickname, account_code, avatar_url")
            .in("id", values: ids).execute().value
    }

    static func fetchMutualFriendCounts(userIds: [UUID]) async throws -> [MutualFriendCountDTO] {
        guard !userIds.isEmpty else { return [] }
        return try await client.rpc("get_mutual_friend_counts", params: ["p_user_ids": userIds]).execute().value
    }

    static func sendFriendRequest(to userId: UUID) async throws {
        try await client.rpc("send_friend_request", params: ["p_addressee_id": userId]).execute()
    }

    static func respondFriendRequest(id: UUID, accept: Bool) async throws {
        struct Params: Encodable { let pRequestId: UUID; let pAccept: Bool }
        try await client.rpc("respond_friend_request", params: Params(pRequestId: id, pAccept: accept)).execute()
    }

    static func cancelFriendRequest(id: UUID) async throws {
        try await client.rpc("cancel_friend_request", params: ["p_request_id": id]).execute()
    }
}
