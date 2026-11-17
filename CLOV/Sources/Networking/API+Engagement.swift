import Foundation
import Supabase

/// Likes, bookmarks and the live vote tally. Requires migrations
/// 20261107000100 through 20261107000400.
extension API {
    private struct EngagementInsert: Encodable {
        let fitCheckId: UUID
        let userId: UUID
    }

    private struct SavedRow: Decodable {
        let fitCheckId: UUID
    }

    private struct LikeCountRow: Decodable {
        let likeCount: Int
    }

    private struct TallyParams: Encodable {
        let pFitCheckId: UUID
    }

    // MARK: - Likes

    /// Idempotent: liking an already-liked post is not an error.
    static func likeFitCheck(id: UUID, userId: UUID) async throws {
#if DEBUG
        if SampleData.isActive { return }
#endif
        try await client.from("fit_check_likes")
            .upsert(EngagementInsert(fitCheckId: id, userId: userId),
                    onConflict: "fit_check_id,user_id", ignoreDuplicates: true)
            .execute()
    }

    static func unlikeFitCheck(id: UUID, userId: UUID) async throws {
#if DEBUG
        if SampleData.isActive { return }
#endif
        try await client.from("fit_check_likes").delete()
            .eq("fit_check_id", value: id).eq("user_id", value: userId).execute()
    }

    /// Which of `ids` the user has liked.
    static func fetchLikedFitCheckIDs(among ids: [UUID], userId: UUID) async throws -> Set<UUID> {
#if DEBUG
        if SampleData.isActive { return [] }
#endif
        guard !ids.isEmpty else { return [] }
        let rows: [SavedRow] = try await client.from("fit_check_likes")
            .select("fit_check_id").eq("user_id", value: userId).in("fit_check_id", values: ids)
            .execute().value
        return Set(rows.map(\.fitCheckId))
    }

    /// The post's like count, or nil when the post is not found or not visible.
    static func fetchLikeCount(id: UUID) async throws -> Int? {
#if DEBUG
        if SampleData.isActive { return nil }
#endif
        let rows: [LikeCountRow] = try await client.from("fit_checks")
            .select("like_count").eq("id", value: id).limit(1).execute().value
        return rows.first?.likeCount
    }

    // MARK: - Bookmarks

    static func bookmarkFitCheck(id: UUID, userId: UUID) async throws {
#if DEBUG
        if SampleData.isActive { return }
#endif
        try await client.from("fit_check_bookmarks")
            .upsert(EngagementInsert(fitCheckId: id, userId: userId),
                    onConflict: "fit_check_id,user_id", ignoreDuplicates: true)
            .execute()
    }

    static func unbookmarkFitCheck(id: UUID, userId: UUID) async throws {
#if DEBUG
        if SampleData.isActive { return }
#endif
        try await client.from("fit_check_bookmarks").delete()
            .eq("fit_check_id", value: id).eq("user_id", value: userId).execute()
    }

    static func fetchBookmarkedFitCheckIDs(among ids: [UUID], userId: UUID) async throws -> Set<UUID> {
#if DEBUG
        if SampleData.isActive { return [] }
#endif
        guard !ids.isEmpty else { return [] }
        let rows: [SavedRow] = try await client.from("fit_check_bookmarks")
            .select("fit_check_id").eq("user_id", value: userId).in("fit_check_id", values: ids)
            .execute().value
        return Set(rows.map(\.fitCheckId))
    }

    /// The user's saved Fit-Checks, most recently saved first. Posts that are no
    /// longer visible (deleted, blocked, left group) simply drop out because the
    /// fit_checks query is subject to RLS.
    static func fetchSavedFeed(userId: UUID, offset: Int, limit: Int) async throws -> FeedPageResult {
#if DEBUG
        if SampleData.isActive { return FeedPageResult(items: [], fetchedCount: 0) }
#endif
        let saved: [SavedRow] = try await client.from("fit_check_bookmarks")
            .select("fit_check_id").eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute().value
        guard !saved.isEmpty else { return FeedPageResult(items: [], fetchedCount: 0) }

        async let blockedTask = fetchBlockedUserIDs()
        let rows: [FeedItemDTO] = try await client.from("fit_checks")
            .select(feedColumns)
            .in("id", values: saved.map(\.fitCheckId))
            .neq("status", value: "draft")
            .execute().value
        // The IN query has no order; restore bookmark recency order.
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = saved.compactMap { byID[$0.fitCheckId] }

        let blocked = try await blockedTask
        let withPrompts = await attachVotePrompts(ordered)
        let visible = try await signFeedPhotos(withPrompts.filter { !blocked.contains($0.creatorId) })
        return FeedPageResult(items: visible, fetchedCount: saved.count)
    }

    // MARK: - Live tally

    /// Per-photo live totals. Empty unless the caller is the creator or has voted.
    static func fetchLiveVoteTally(fitCheckId: UUID) async throws -> [LivePhotoTally] {
#if DEBUG
        if SampleData.isActive { return [] }
#endif
        return try await client.rpc("get_live_vote_tally", params: TallyParams(pFitCheckId: fitCheckId))
            .execute().value
    }
}
