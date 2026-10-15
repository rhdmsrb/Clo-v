import Foundation
import UIKit
import Supabase

enum APIError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}

struct WardrobeTryOnResponse: Decodable {
    let jobId: String
    let status: String
    let imageUrl: String?
    let message: String?
}

private struct TryOnFunctionError: Decodable {
    let message: String?
}

enum API {
    private static var client: SupabaseClient { SupabaseManager.client }

    static func createWardrobeTryOn(photo: UIImage, itemIDs: [UUID]) async throws -> WardrobeTryOnResponse {
        guard !itemIDs.isEmpty else { throw APIError.message("Choose at least one clothing piece first.") }
        _ = try await client.auth.session
        let imageData = try compressedTryOnPhoto(photo)
        struct Request: Encodable {
            let action: String
            let bodyPhoto: String
            let itemIDs: [UUID]
        }
        let bodyPhoto = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        return try await invokeWardrobeTryOn(
            Request(action: "submit", bodyPhoto: bodyPhoto, itemIDs: itemIDs), timeout: 45
        )
    }

    static func checkWardrobeTryOn(jobID: String) async throws -> WardrobeTryOnResponse {
        struct Request: Encodable { let action: String; let jobID: String }
        return try await invokeWardrobeTryOn(Request(action: "status", jobID: jobID), timeout: 30)
    }

    private static func invokeWardrobeTryOn(_ body: some Encodable, timeout: TimeInterval) async throws -> WardrobeTryOnResponse {
        do {
            return try await client.functions.invoke(
                "wardrobe-try-on",
                options: FunctionInvokeOptions(body: body, timeoutInterval: timeout)
            )
        } catch let error as FunctionsError {
            if case let .httpError(_, data) = error,
               let response = try? JSONDecoder().decode(TryOnFunctionError.self, from: data),
               let message = response.message {
                throw APIError.message(message)
            }
            throw APIError.message("Try-on service isn't available yet. Please try again later.")
        }
    }

    /// Reduce large camera and library photos progressively so users don't
    /// have to manually find a smaller image. Keep enough resolution for the
    /// provider to identify the person and clothing silhouette.
    private static func compressedTryOnPhoto(_ photo: UIImage) throws -> Data {
        let oriented = photo.normalizedOrientation()
        for dimension: CGFloat in [1200, 1024, 900, 768, 640, 512] {
            let resized = oriented.resized(maxDimension: dimension)
            for quality: CGFloat in [0.78, 0.68, 0.58, 0.48] {
                if let data = resized.jpegData(compressionQuality: quality), data.count <= 1_300_000 {
                    return data
                }
            }
        }
        throw APIError.message("Couldn't prepare that photo for try-on. Please choose another photo.")
    }

    struct FeedPageResult {
        let items: [FeedItemDTO]
        let fetchedCount: Int
    }

    // MARK: - Profile / Onboarding

    static func fetchProfile(id: UUID) async throws -> Profile? {
        // PostgREST's request adapter falls back to the public anon key when
        // its access-token provider cannot resolve a valid session. For this
        // authenticated query, fail with the auth error instead of issuing an
        // anonymous request that only surfaces as a misleading SQL privilege
        // error (42501).
        let session = try await client.auth.session
        guard session.user.id == id else {
            throw APIError.message("Your sign-in session changed. Please log in again.")
        }
        let rows: [Profile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: id)
            .execute()
            .value
        return rows.first
    }

    static func saveOnboarding(nickname: String, styles: [String]) async throws {
        struct Payload: Encodable {
            let nickname: String
            let stylePreferences: [String]
        }
        do {
            _ = try await client
                .rpc("save_onboarding", params: Payload(nickname: nickname, stylePreferences: styles))
                .execute()
        } catch {
            if error.isUniqueViolation {
                throw APIError.message("That nickname is already taken.")
            }
            throw error
        }
    }

    /// Remove actual files through Storage before deleting the account. SQL
    /// deletion of storage.objects only removes metadata, leaving files behind.
    /// A failed file removal leaves the account available for a safe retry.
    static func deleteAccount() async throws {
        let session = try await client.auth.session
        let userId = session.user.id.storagePathComponent
        for bucket in ["avatars", "fit-check-photos", "wardrobe-items"] {
            try await deleteStorageFolder(bucket: bucket, path: userId)
        }
        _ = try await client.rpc("delete_my_account").execute()
        // Clear the local token when the server has deleted the account. This
        // may throw if the auth session was already invalidated, which is safe
        // to ignore because the account is already gone.
        try? await client.auth.signOut()
    }

    private static func deleteStorageFolder(bucket: String, path: String) async throws {
        let storage = client.storage.from(bucket)
        var batches = 0
        while true {
            guard batches < 10_000 else {
                throw APIError.message("Couldn't finish removing your photos. Please try again.")
            }
            batches += 1
            // Always fetch the first page. Removing it makes the next page
            // become the first, so no object is skipped as the list shrinks.
            let entries = try await storage.list(path: path, options: SearchOptions(limit: 1000))
            if entries.isEmpty { return }
            let folders = entries.filter { $0.id == nil }
            for folder in folders {
                try await deleteStorageFolder(bucket: bucket, path: "\(path)/\(folder.name)")
            }
            let filePaths = entries.filter { $0.id != nil }.map { "\(path)/\($0.name)" }
            if !filePaths.isEmpty {
                let removed = try await storage.remove(paths: filePaths)
                guard !removed.isEmpty else {
                    throw APIError.message("Couldn't remove your photos. Please try again.")
                }
            }
            if folders.isEmpty && filePaths.isEmpty {
                throw APIError.message("Couldn't remove your photos. Please try again.")
            }
        }
    }

    static func updateAvatar(id: UUID, image: UIImage) async throws -> String {
        let publicURL = try await uploadImage(image, bucket: "avatars", pathPrefix: id.storagePathComponent, aspectRatio: 1.0)
        try await client
            .from("profiles")
            .update(["avatar_url": publicURL])
            .eq("id", value: id)
            .execute()
        return publicURL
    }

    // MARK: - Feed

    // Optional vote prompts are loaded separately so older Supabase schemas
    // can still serve the core discovery feed during a gradual rollout.
    private static let feedColumns = "id, creator_id, caption, occasion, created_at, expires_at, fit_check_photos(id, fit_check_id, image_url, position), fit_check_votes(photo_id, voter_id), fit_check_comments(id), profiles(nickname, avatar_url)"

    private static var notExpiredFilter: String {
        "expires_at.is.null,expires_at.gt.\(ISO8601DateFormatter().string(from: Date()))"
    }

    static func fetchFeed() async throws -> [FeedItemDTO] {
        async let blockedTask = fetchBlockedUserIDs()
        let userId = try await client.auth.session.user.id
        async let friendTask = fetchFriendIDs(userId: userId)
        let friendIDs = try await friendTask
        var query = client.from("fit_checks").select(feedColumns).eq("status", value: "live").or(notExpiredFilter)
        if friendIDs.isEmpty { query = query.eq("is_public", value: true) }
        else { query = query.or("is_public.eq.true,creator_id.in.(\(friendIDs.map(\.uuidString).joined(separator: ",")))") }
        let rows: [FeedItemDTO] = try await query
            .order("created_at", ascending: false).limit(50).execute().value
        let blocked = try await blockedTask
        let promptedRows = await attachVotePrompts(rows)
        return try await signFeedPhotos(promptedRows.filter { !blocked.contains($0.creatorId) })
    }

    static func fetchFeedPage(offset: Int, limit: Int, search: String, occasion: String?, followingIDs: Set<UUID>?, friendIDs: Set<UUID> = []) async throws -> FeedPageResult {
        let followedOrFriends = (followingIDs ?? []).union(friendIDs)
        if followingIDs != nil, followedOrFriends.isEmpty { return FeedPageResult(items: [], fetchedCount: 0) }
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var query = client.from("fit_checks")
            .select(feedColumns).eq("status", value: "live")
            .or(notExpiredFilter)
        if followingIDs != nil {
            query = query.in("creator_id", values: Array(followedOrFriends))
        } else if !friendIDs.isEmpty {
            query = query.or("is_public.eq.true,creator_id.in.(\(friendIDs.map(\.uuidString).joined(separator: ",")))")
        } else {
            query = query.eq("is_public", value: true)
        }
        if let occasion, !occasion.isEmpty {
            query = query.eq("occasion", value: occasion)
        }
        if !trimmedSearch.isEmpty {
            query = query.ilike("caption", pattern: "%\(trimmedSearch)%")
        }
        let rows: [FeedItemDTO] = try await query
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + max(0, limit - 1))
            .execute().value
        let blocked = try await fetchBlockedUserIDs()
        let promptedRows = await attachVotePrompts(rows)
        let visible = try await signFeedPhotos(promptedRows.filter { !blocked.contains($0.creatorId) })
        return FeedPageResult(items: visible, fetchedCount: rows.count)
    }

    static func fetchFollowingFeed(userId: UUID) async throws -> [FeedItemDTO] {
        let following = try await fetchFollowingIDs(userId: userId)
        let friendIDs = try await fetchFriendIDs(userId: userId)
        let visibleAuthors = following.union(friendIDs)
        guard !visibleAuthors.isEmpty else { return [] }
        async let blockedTask = fetchBlockedUserIDs()
        let rows: [FeedItemDTO] = try await client.from("fit_checks")
            .select(feedColumns).eq("status", value: "live")
            .in("creator_id", values: Array(visibleAuthors))
            .or(notExpiredFilter)
            .order("created_at", ascending: false).limit(50).execute().value
        let blocked = try await blockedTask
        let promptedRows = await attachVotePrompts(rows)
        return try await signFeedPhotos(promptedRows.filter { !blocked.contains($0.creatorId) })
    }

    static func fetchFollowingIDs(userId: UUID) async throws -> Set<UUID> {
        let rows: [ProfileFollow] = try await client.from("profile_follows")
            .select("follower_id, following_id, created_at")
            .eq("follower_id", value: userId)
            .execute().value
        return Set(rows.map(\.followingId))
    }

    static func fetchFollowerIDs(userId: UUID) async throws -> Set<UUID> {
        let rows: [ProfileFollow] = try await client.from("profile_follows")
            .select("follower_id, following_id, created_at")
            .eq("following_id", value: userId)
            .execute().value
        return Set(rows.map(\.followerId))
    }

    static func fetchFriendIDs(userId: UUID) async throws -> Set<UUID> {
        let rows: [FriendshipDTO] = try await client.from("friendships").select("user_low, user_high")
            .or("user_low.eq.\(userId.uuidString),user_high.eq.\(userId.uuidString)")
            .execute().value
        return Set(rows.map { $0.userLow == userId ? $0.userHigh : $0.userLow })
    }

    static func setFollowing(_ following: Bool, followerId: UUID, followingId: UUID) async throws {
        guard followerId != followingId else { return }
        if following {
            struct Payload: Encodable { let followerId: UUID; let followingId: UUID }
            try await client.from("profile_follows")
                .upsert(Payload(followerId: followerId, followingId: followingId), onConflict: "follower_id,following_id")
                .execute()
        } else {
            try await client.from("profile_follows")
                .delete().eq("follower_id", value: followerId).eq("following_id", value: followingId)
                .execute()
        }
    }

    static func logFeedEvent(userId: UUID, fitCheckId: UUID, event: String, value: Double? = nil) async throws {
        struct Payload: Encodable {
            let userId: UUID
            let fitCheckId: UUID
            let event: String
            let value: Double?
        }
        try await client.from("feed_events").insert(Payload(userId: userId, fitCheckId: fitCheckId, event: event, value: value)).execute()
    }

    static func fetchFeedSignalScores(userId: UUID) async throws -> [UUID: Int] {
        struct Row: Decodable {
            let fitCheckId: UUID
            let event: String
        }
        let rows: [Row] = try await client.from("feed_events")
            .select("fit_check_id, event")
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(500)
            .execute().value
        let weights = [
            "impression": -1,
            "open_detail": 3,
            "vote": 6,
            "save": 4,
            "share": 5,
            "follow": 2,
            "unfollow": -2,
            "not_interested": -8
        ]
        return rows.reduce(into: [:]) { scores, row in
            scores[row.fitCheckId, default: 0] += weights[row.event, default: 0]
        }
    }

    static func fetchGroupFeed(groupId: UUID) async throws -> [FeedItemDTO] {
        async let blockedTask = fetchBlockedUserIDs()
        let rows: [FeedItemDTO] = try await client.from("fit_checks")
            .select(feedColumns).eq("status", value: "live")
            .eq("group_id", value: groupId).or(notExpiredFilter)
            .order("created_at", ascending: false).limit(50).execute().value
        let blocked = try await blockedTask
        let promptedRows = await attachVotePrompts(rows)
        return try await signFeedPhotos(promptedRows.filter { !blocked.contains($0.creatorId) })
    }

    private static func fetchBlockedUserIDs() async throws -> Set<UUID> {
        struct Row: Decodable { let blockedId: UUID }
        let rows: [Row] = try await client
            .from("blocked_users")
            .select("blocked_id")
            .execute()
            .value
        return Set(rows.map(\.blockedId))
    }

    static func fetchMyFitChecksWithStatus(creatorId: UUID) async throws -> [MyFitCheck] {
        struct Row: Decodable {
            let id: UUID
            var caption: String?
            var status: String
            var fitCheckPhotos: [FitCheckPhoto]
        }
        let rows: [Row] = try await client
            .from("fit_checks")
            .select("id, caption, status, fit_check_photos(id, fit_check_id, image_url, position)")
            .eq("creator_id", value: creatorId)
            .neq("status", value: "draft")
            .order("created_at", ascending: false)
            .execute()
            .value
        let urls = try await signedPhotoURLs(rows.flatMap(\.fitCheckPhotos).map(\.imageUrl))
        return rows.map { row in
            MyFitCheck(
                id: row.id,
                caption: row.caption,
                status: row.status,
                thumbnailURL: row.fitCheckPhotos.first(where: { $0.position == 1 }).flatMap { urls[$0.imageUrl] }
            )
        }
    }

    // MARK: - Style insights

    static func fetchWeeklyStyleReport(userId: UUID) async throws -> WeeklyStyleReport {
        struct ActivityRow: Decodable {
            let createdAt: Date
            let occasion: String?
        }

        let calendar = Calendar.current
        let now = Date()
        let weekStart = calendar.date(byAdding: .day, value: -6, to: now) ?? now
        let historyStart = calendar.date(byAdding: .day, value: -60, to: now) ?? now
        let since = ISO8601DateFormatter().string(from: historyStart)

        async let votesTask: [ActivityRow] = client
            .from("fit_check_votes")
            .select("created_at")
            .eq("voter_id", value: userId)
            .gte("created_at", value: since)
            .execute().value
        async let postsTask: [ActivityRow] = client
            .from("fit_checks")
            .select("created_at, occasion")
            .eq("creator_id", value: userId)
            .neq("status", value: "draft")
            .gte("created_at", value: since)
            .execute().value
        async let commentsTask: [ActivityRow] = client
            .from("fit_check_comments")
            .select("created_at")
            .eq("commenter_id", value: userId)
            .gte("created_at", value: since)
            .execute().value
        async let wardrobeTask: [ActivityRow] = client
            .from("wardrobe_items")
            .select("created_at")
            .eq("owner_id", value: userId)
            .gte("created_at", value: since)
            .execute().value

        let (votes, posts, comments, wardrobe) = try await (votesTask, postsTask, commentsTask, wardrobeTask)
        let weekStartDay = calendar.startOfDay(for: weekStart)
        let inWeek: (ActivityRow) -> Bool = { row in row.createdAt >= weekStartDay }
        let activeDates = (votes + posts + comments + wardrobe).map { calendar.startOfDay(for: $0.createdAt) }
        let activeDateSet = Set(activeDates)

        var streak = 0
        var cursor = calendar.startOfDay(for: now)
        if !activeDateSet.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while activeDateSet.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        let occasionCounts = posts.filter(inWeek).compactMap(\.occasion).reduce(into: [:]) { counts, occasion in
            counts[occasion, default: 0] += 1
        }
        let topOccasion = occasionCounts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key

        return WeeklyStyleReport(
            votesCast: votes.filter(inWeek).count,
            fitChecksPosted: posts.filter(inWeek).count,
            commentsWritten: comments.filter(inWeek).count,
            wardrobePiecesAdded: wardrobe.filter(inWeek).count,
            currentStreak: streak,
            topOccasion: topOccasion
        )
    }

    // MARK: - Fit-Check detail / voting / comments

    static func fetchFitCheckDetail(id: UUID) async throws -> FitCheckDetailDTO? {
        let rows: [FitCheckDetailDTO] = try await client
            .from("fit_checks")
            .select("id, caption, occasion, status, creator_id, expires_at, fit_check_photos(id, fit_check_id, image_url, position), profiles(nickname, avatar_url)")
            .eq("id", value: id)
            .execute()
            .value
        guard var detail = rows.first else { return nil }
        detail.votePrompt = try? await fetchVotePrompt(fitCheckId: id)
        detail.fitCheckPhotos = try await signedPhotos(detail.fitCheckPhotos)
        return detail
    }

    static func fetchVotes(fitCheckId: UUID) async throws -> [VoteRef] {
        try await client
            .from("fit_check_votes")
            .select("photo_id, voter_id")
            .eq("fit_check_id", value: fitCheckId)
            .execute()
            .value
    }

    static func fetchComments(fitCheckId: UUID) async throws -> [CommentDTO] {
        try await client
            .from("fit_check_comments")
            .select("id, body, created_at, profiles(nickname, avatar_url)")
            .eq("fit_check_id", value: fitCheckId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func castVote(fitCheckId: UUID, photoId: UUID, voterId: UUID, creatorId: UUID, status: String, expiresAt: Date? = nil) async throws {
        if creatorId == voterId {
            throw APIError.message("You can't vote on your own Fit-Check.")
        }
        if status != "live" || isExpired(expiresAt) {
            throw APIError.message("This Fit-Check isn't live anymore.")
        }
        struct Payload: Encodable {
            let fitCheckId: UUID
            let photoId: UUID
            let voterId: UUID
        }
        do {
            try await client
                .from("fit_check_votes")
                .insert(Payload(fitCheckId: fitCheckId, photoId: photoId, voterId: voterId))
                .execute()
        } catch {
            if error.isUniqueViolation {
                throw APIError.message("You already voted on this Fit-Check.")
            }
            throw error
        }
        try? await logFeedEvent(userId: voterId, fitCheckId: fitCheckId, event: "vote")
        // The creator's "someone voted" notification is created by a DB
        // trigger on fit_check_votes (see 0010_db_invariants.sql) — no
        // second write from here.
    }

    static func saveVoteReason(fitCheckId: UUID, photoId: UUID, tags: [String], comment: String) async throws {
        struct Params: Encodable {
            let pFitCheckId: UUID
            let pPhotoId: UUID
            let pReasonTags: [String]
            let pReasonComment: String
            enum CodingKeys: String, CodingKey {
                case pFitCheckId = "p_fit_check_id"
                case pPhotoId = "p_photo_id"
                case pReasonTags = "p_reason_tags"
                case pReasonComment = "p_reason_comment"
            }
        }
        try await client.rpc("save_vote_reason", params: Params(pFitCheckId: fitCheckId, pPhotoId: photoId, pReasonTags: tags, pReasonComment: comment)).execute()
    }

    static func registerDeviceToken(_ token: String, userId: UUID) async throws {
        struct Payload: Encodable {
            let userId: UUID
            let token: String
            let platform = "ios"
            let updatedAt = Date()
        }
        try await client.from("device_tokens").upsert(Payload(userId: userId, token: token), onConflict: "token").execute()
    }

    static func addComment(fitCheckId: UUID, photoId: UUID, commenterId: UUID, body: String) async throws {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.message("Comment can't be empty.") }
        guard trimmed.count <= 280 else { throw APIError.message("Keep the comment under 280 characters.") }

        guard let fitCheck = try await fetchFitCheckDetail(id: fitCheckId) else {
            throw APIError.message("Fit-Check not found.")
        }
        guard !isExpired(fitCheck.expiresAt) else {
            throw APIError.message("This Fit-Check isn't live anymore.")
        }

        struct Payload: Encodable {
            let fitCheckId: UUID
            let photoId: UUID
            let commenterId: UUID
            let body: String
        }

        try await client
            .from("fit_check_comments")
            .insert(Payload(fitCheckId: fitCheckId, photoId: photoId, commenterId: commenterId, body: trimmed))
            .execute()

        // The creator's "someone commented" notification is created by a
        // DB trigger on fit_check_comments (see 0010_db_invariants.sql),
        // which also skips the self-comment case — no second write here.
    }

    static func reportFitCheck(id: UUID, reason: String) async throws {
        struct Params: Encodable {
            let pFitCheckId: UUID
            let pReason: String
            enum CodingKeys: String, CodingKey {
                case pFitCheckId = "p_fit_check_id"
                case pReason = "p_reason"
            }
        }
        try await client.rpc("submit_content_report", params: Params(pFitCheckId: id, pReason: reason)).execute()
    }

    static func blockUser(id: UUID) async throws {
        try await client.rpc("block_user", params: ["p_blocked_id": id]).execute()
    }

    // MARK: - Notifications

    static func fetchNotifications(recipientId: UUID) async throws -> [NotificationDTO] {
        try await client
            .from("notifications")
            .select("id, type, is_read, created_at, fit_check_id, actor:profiles!notifications_actor_id_fkey(nickname, avatar_url)")
            .eq("recipient_id", value: recipientId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func fetchUnreadNotificationCount(recipientId: UUID) async throws -> Int {
        let response = try await client
            .from("notifications")
            .select("id", head: true, count: .exact)
            .eq("recipient_id", value: recipientId)
            .eq("is_read", value: false)
            .execute()
        return response.count ?? 0
    }

    static func markAllNotificationsRead(recipientId: UUID) async throws {
        try await client
            .from("notifications")
            .update(["is_read": true])
            .eq("recipient_id", value: recipientId)
            .eq("is_read", value: false)
            .execute()
    }

    static func markNotificationRead(id: UUID, recipientId: UUID) async throws {
        try await client
            .from("notifications")
            .update(["is_read": true])
            .eq("id", value: id)
            .eq("recipient_id", value: recipientId)
            .eq("is_read", value: false)
            .execute()
    }

    static func terminateFitCheck(id: UUID, creatorId: UUID) async throws {
        try await client.from("fit_checks")
            .update(["status": "archived", "ended_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: id).eq("creator_id", value: creatorId).execute()
    }

    /// Permanently removes a Fit-Check the caller owns — live or archived —
    /// along with its photos, votes, comments, and notifications (all
    /// `on delete cascade` from `fit_checks`, see 0003/0005/0007 migrations).
    /// The owner-only delete policy in 0009 authorizes this operation.
    static func deleteFitCheck(id: UUID, creatorId: UUID) async throws {
        let session = try await client.auth.session
        guard creatorId == session.user.id else { throw APIError.message("Please sign in again.") }

        struct PhotoRow: Decodable { let imageUrl: String }
        let photos: [PhotoRow] = try await client
            .from("fit_check_photos")
            .select("image_url")
            .eq("fit_check_id", value: id)
            .execute()
            .value

        try await client
            .from("fit_checks")
            .delete()
            .eq("id", value: id)
            .eq("creator_id", value: creatorId)
            .execute()

        // Cleanup is best-effort. Until a matching Storage delete policy is
        // deployed, deleting the database row can leave orphaned objects.
        let paths = photos.compactMap { photoPath($0.imageUrl) }
        if !paths.isEmpty {
            _ = try? await client.storage.from("fit-check-photos").remove(paths: paths)
        }
    }

    // MARK: - Create Fit-Check

    static func createFitCheck(creatorId: UUID, caption: String?, occasion: String? = nil, groupId: UUID?, audience: String = "public", votePrompt: String? = nil, votingDuration: TimeInterval, photos: [UIImage]) async throws {
        guard photos.count == 2 || photos.count == 4 else { throw APIError.message("Upload exactly 2 or 4 photos.") }
        guard (caption ?? "").count <= 280 else { throw APIError.message("Keep the caption under 280 characters.") }
        let session = try await client.auth.session
        guard creatorId == session.user.id else { throw APIError.message("Please sign in again.") }

        if let groupId {
            let memberships: [GroupMember] = try await client.from("group_members").select()
                .eq("group_id", value: groupId).eq("profile_id", value: creatorId).execute().value
            guard !memberships.isEmpty else { throw APIError.message("You're not a member of that group.") }
        }
        guard ["public", "friends", "group", "private"].contains(audience),
              (audience == "group") == (groupId != nil) else {
            throw APIError.message("Choose a valid audience for this Fit-Check.")
        }
        struct DraftParams: Encodable {
            let id: UUID
            let caption: String?
            let groupId: UUID?
            let occasion: String?
            let audience: String
            let votePrompt: String?
            enum CodingKeys: String, CodingKey { case id = "p_id"; case caption = "p_caption"; case groupId = "p_group_id"; case occasion = "p_occasion"; case audience = "p_audience"; case votePrompt = "p_vote_prompt" }
        }
        let fitCheckId: UUID = try await client.rpc("create_fit_check_draft", params: DraftParams(id: UUID(), caption: caption, groupId: groupId, occasion: occasion, audience: audience, votePrompt: votePrompt)).execute().value
        for (index, photo) in photos.enumerated() {
            do {
                let path = try await uploadImage(photo, bucket: "fit-check-photos", pathPrefix: "\(creatorId.storagePathComponent)/\(fitCheckId.storagePathComponent)", aspectRatio: 3.0 / 4.0)
                struct PhotoInsert: Encodable { let fitCheckId: UUID; let imageUrl: String; let position: Int }
                try await client.from("fit_check_photos")
                    .insert(PhotoInsert(fitCheckId: fitCheckId, imageUrl: path, position: index + 1)).execute()
            } catch {
                throw error
            }
        }
        struct PublishParams: Encodable {
            let id: UUID
            let durationSeconds: Int
            enum CodingKeys: String, CodingKey { case id = "p_id"; case durationSeconds = "p_duration_seconds" }
        }
        try await client.rpc("publish_fit_check", params: PublishParams(id: fitCheckId, durationSeconds: Int(votingDuration))).execute()
    }

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

    // MARK: - Friends

    // MARK: - Wardrobe

    static func fetchWardrobeItems(ownerId: UUID) async throws -> [WardrobeItem] {
        let rows: [WardrobeItem] = try await client
            .from("wardrobe_items")
            .select()
            .eq("owner_id", value: ownerId)
            .order("created_at", ascending: false)
            .execute()
            .value
        let urls = try await signedStorageURLs(rows.map(\.imageUrl), bucket: "wardrobe-items")
        return rows.map { item in
            var result = item
            result.imageUrl = urls[item.imageUrl] ?? ""
            return result
        }
    }

    static func createWardrobeItem(ownerId: UUID, image: UIImage, name: String?, category: String,
                                   subcategory: String?, color: String?, season: String?, brand: String?,
                                   wearFrequency: String?, tags: [String] = []) async throws {
        let session = try await client.auth.session
        guard session.user.id == ownerId else { throw APIError.message("Please sign in again.") }
        let itemId = UUID()
        let path = try await uploadImage(image, bucket: "wardrobe-items",
                                         pathPrefix: "\(ownerId.storagePathComponent)/\(itemId.storagePathComponent)",
                                         aspectRatio: 3.0 / 4.0, persistPublicURL: false,
                                         preserveAspectRatio: true)
        struct Insert: Encodable {
            let id: UUID; let ownerId: UUID; let imageUrl: String; let name: String?
            let category: String; let subcategory: String?; let color: String?; let season: String?
            let brand: String?; let wearFrequency: String?; let tags: [String]
        }
        do {
            try await client.from("wardrobe_items").insert(Insert(
                id: itemId, ownerId: ownerId, imageUrl: path, name: name,
                category: category, subcategory: subcategory, color: color, season: season,
                brand: brand, wearFrequency: wearFrequency, tags: tags
            )).execute()
        } catch {
            _ = try? await client.storage.from("wardrobe-items").remove(paths: [path])
            throw error
        }
    }

    static func updateWardrobeItem(id: UUID, ownerId: UUID, image: UIImage?, name: String?, category: String,
                                   subcategory: String?, color: String?, season: String?, brand: String?,
                                   wearFrequency: String?, tags: [String]) async throws {
        let session = try await client.auth.session
        guard session.user.id == ownerId else { throw APIError.message("Please sign in again.") }
        struct ImageRow: Decodable { let imageUrl: String }
        let existing: [ImageRow] = try await client.from("wardrobe_items")
            .select("image_url").eq("id", value: id).eq("owner_id", value: ownerId).execute().value
        guard let oldImage = existing.first?.imageUrl else { throw APIError.message("This wardrobe item no longer exists.") }
        var newImage: String?
        if let image {
            newImage = try await uploadImage(image, bucket: "wardrobe-items",
                                             pathPrefix: "\(ownerId.storagePathComponent)/\(id.storagePathComponent)",
                                             aspectRatio: 3.0 / 4.0, persistPublicURL: false,
                                             preserveAspectRatio: true)
        }
        struct Update: Encodable {
            let imageUrl: String; let name: String?; let category: String
            let subcategory: String?; let color: String?; let season: String?
            let brand: String?; let wearFrequency: String?; let tags: [String]
        }
        do {
            try await client.from("wardrobe_items").update(Update(
                imageUrl: newImage ?? oldImage, name: name, category: category,
                subcategory: subcategory, color: color, season: season,
                brand: brand, wearFrequency: wearFrequency, tags: tags
            )).eq("id", value: id).eq("owner_id", value: ownerId).execute()
        } catch {
            if let newImage { _ = try? await client.storage.from("wardrobe-items").remove(paths: [newImage]) }
            throw error
        }
        if newImage != nil, let oldPath = storagePath(oldImage, bucket: "wardrobe-items") {
            _ = try? await client.storage.from("wardrobe-items").remove(paths: [oldPath])
        }
    }

    static func deleteWardrobeItem(id: UUID, ownerId: UUID) async throws {
        let session = try await client.auth.session
        guard session.user.id == ownerId else { throw APIError.message("Please sign in again.") }
        struct ImageRow: Decodable { let imageUrl: String }
        let images: [ImageRow] = try await client.from("wardrobe_items")
            .select("image_url").eq("id", value: id).eq("owner_id", value: ownerId).execute().value
        try await client.from("wardrobe_items").delete()
            .eq("id", value: id).eq("owner_id", value: ownerId).execute()
        let paths = images.compactMap { storagePath($0.imageUrl, bucket: "wardrobe-items") }
        if !paths.isEmpty { _ = try? await client.storage.from("wardrobe-items").remove(paths: paths) }
    }

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
        return try await client.from("profiles").select("id, nickname, account_code, avatar_url")
            .or("nickname.ilike.%\(trimmed)%,account_code.ilike.%\(trimmed)%")
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

    // MARK: - Storage

    // Accept stored paths and legacy public URLs from this project's bucket.
    // Never persist a signed URL: it expires and is specific to a read request.
    private static func storagePath(_ value: String, bucket: String) -> String? {
        if !value.contains("://") { return value.isEmpty ? nil : value }
        guard let url = URL(string: value), url.host == AppConfig.supabaseURL.host else { return nil }
        let prefix = "/storage/v1/object/public/\(bucket)/"
        guard url.path.hasPrefix(prefix) else { return nil }
        return String(url.path.dropFirst(prefix.count))
    }

    private static func photoPath(_ value: String) -> String? {
        storagePath(value, bucket: "fit-check-photos")
    }

    private static func signedStorageURLs(_ values: [String], bucket: String) async throws -> [String: String] {
        let paths = Array(Set(values.compactMap { storagePath($0, bucket: bucket) }))
        guard !paths.isEmpty else { return [:] }
        var signed: [String: String] = [:]
        for start in stride(from: 0, to: paths.count, by: 100) {
            let batch = Array(paths[start..<min(start + 100, paths.count)])
            // A stale or missing object should not hide the complete wardrobe.
            // Supabase returns signed URLs per object, so keep successful results
            // and leave only the failed image without a URL.
            do {
                let results: [SignedURLResult] = try await client.storage.from(bucket)
                    .createSignedURLs(paths: batch, expiresIn: 86400)
                for result in results {
                    if let url = result.signedURL { signed[result.path] = url.absoluteString }
                }
            } catch {
                continue
            }
        }
        return Dictionary(uniqueKeysWithValues: Set(values).compactMap { value in
            guard let path = storagePath(value, bucket: bucket), let url = signed[path] else { return nil }
            return (value, url)
        })
    }

    private static func signedPhotoURLs(_ values: [String]) async throws -> [String: String] {
        let paths = Array(Set(values.compactMap(photoPath)))
        guard !paths.isEmpty else { return [:] }
        var signed: [String: String] = [:]
        // Bound each Storage request even for a large account gallery.
        for start in stride(from: 0, to: paths.count, by: 100) {
            let batch = Array(paths[start..<min(start + 100, paths.count)])
            do {
                let results: [SignedURLResult] = try await client.storage.from("fit-check-photos")
                    .createSignedURLs(paths: batch, expiresIn: 3600)
                for result in results {
                    if let url = result.signedURL { signed[result.path] = url.absoluteString }
                }
            } catch {
                continue
            }
        }
        return Dictionary(uniqueKeysWithValues: Set(values).compactMap { value in
            guard let path = photoPath(value), let url = signed[path] else { return nil }
            return (value, url)
        })
    }

    private static func attachVotePrompts(_ rows: [FeedItemDTO]) async -> [FeedItemDTO] {
        guard !rows.isEmpty else { return rows }
        do {
            struct PromptRow: Decodable { let id: UUID; let votePrompt: String? }
            let prompts: [PromptRow] = try await client.from("fit_checks")
                .select("id, vote_prompt")
                .in("id", values: rows.map(\.id))
                .execute().value
            let byID = Dictionary(uniqueKeysWithValues: prompts.map { ($0.id, $0.votePrompt) })
            return rows.map { row in
                var updated = row
                updated.votePrompt = byID[row.id] ?? nil
                return updated
            }
        } catch {
            // vote_prompt is an optional enhancement. Older deployments
            // lack the column, but discovery should remain available.
            return rows
        }
    }

    private static func fetchVotePrompt(fitCheckId: UUID) async throws -> String? {
        struct PromptRow: Decodable { let votePrompt: String? }
        let rows: [PromptRow] = try await client.from("fit_checks")
            .select("vote_prompt").eq("id", value: fitCheckId).limit(1).execute().value
        return rows.first?.votePrompt
    }

    private static func signedPhotos(_ photos: [FitCheckPhoto]) async throws -> [FitCheckPhoto] {
        let urls = try await signedPhotoURLs(photos.map(\.imageUrl))
        return photos.map { photo in
            var result = photo
            result.imageUrl = urls[photo.imageUrl] ?? ""
            return result
        }
    }

    private static func signFeedPhotos(_ rows: [FeedItemDTO]) async throws -> [FeedItemDTO] {
        let urls = try await signedPhotoURLs(rows.flatMap(\.fitCheckPhotos).map(\.imageUrl))
        return rows.map { row in
            var result = row
            result.fitCheckPhotos = row.fitCheckPhotos.map { photo in
                var signed = photo
                signed.imageUrl = urls[photo.imageUrl] ?? ""
                return signed
            }
            return result
        }
    }

    /// Normalizes orientation and downscales BEFORE upload. Feed photos and
    /// avatars are cropped to their presentation ratio; wardrobe pieces can
    /// preserve their full shape so the catalog never cuts off a garment.
    private static func uploadImage(_ image: UIImage, bucket: String, pathPrefix: String,
                                    aspectRatio: CGFloat, persistPublicURL: Bool = true,
                                    preserveAspectRatio: Bool = false) async throws -> String {
        let oriented = image.normalizedOrientation()
        let prepared = (preserveAspectRatio ? oriented : oriented.croppedToAspectRatio(aspectRatio))
            .resized(maxDimension: 1600)

        guard let data = prepared.jpegData(compressionQuality: 0.85) else {
            throw APIError.message("Couldn't process that image.")
        }
        let path = "\(pathPrefix)/\(UUID().storagePathComponent).jpg"
        try await client.storage.from(bucket).upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        return bucket == "fit-check-photos" || !persistPublicURL ? path : try client.storage.from(bucket).getPublicURL(path: path).absoluteString
    }
}

private extension UUID {
    /// Lowercased UUID string for Supabase Storage object paths. Swift's
    /// `UUID` prints uppercase, but Storage RLS policies compare the
    /// folder segment against `auth.uid()::text`, which Postgres renders
    /// lowercase — an uppercase path fails the policy (see
    /// 0009_enable_rls.sql storage policies).
    var storagePathComponent: String { uuidString.lowercased() }
}

private extension Error {
    /// Postgres unique_violation (23505) surfaced through PostgrestError.
    var isUniqueViolation: Bool {
        if let postgrestError = self as? PostgrestError {
            return postgrestError.code == "23505"
        }
        return false
    }
}
