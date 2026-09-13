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

enum API {
    private static var client: SupabaseClient { SupabaseManager.client }

    // MARK: - Profile / Onboarding

    static func fetchProfile(id: UUID) async throws -> Profile? {
        let rows: [Profile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: id)
            .execute()
            .value
        return rows.first
    }

    static func saveOnboarding(id: UUID, nickname: String, styles: [String]) async throws {
        struct Payload: Encodable {
            let id: UUID
            let nickname: String
            let stylePreferences: [String]
        }
        do {
            try await client
                .from("profiles")
                .upsert(Payload(id: id, nickname: nickname, stylePreferences: styles), onConflict: "id")
                .execute()
        } catch {
            if error.isUniqueViolation {
                throw APIError.message("That nickname is already taken.")
            }
            throw error
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

    private static let feedColumns = "id, creator_id, caption, created_at, expires_at, fit_check_photos(id, fit_check_id, image_url, position), fit_check_votes(photo_id, voter_id), fit_check_comments(id), profiles(nickname, avatar_url)"

    private static var notExpiredFilter: String {
        "expires_at.is.null,expires_at.gt.\(ISO8601DateFormatter().string(from: Date()))"
    }

    static func fetchFeed() async throws -> [FeedItemDTO] {
        let rows: [FeedItemDTO] = try await client.from("fit_checks")
            .select(feedColumns).eq("status", value: "live")
            .eq("is_public", value: true).or(notExpiredFilter).execute().value
        return try await signFeedPhotos(rows)
    }

    static func fetchGroupFeed(groupId: UUID) async throws -> [FeedItemDTO] {
        let rows: [FeedItemDTO] = try await client.from("fit_checks")
            .select(feedColumns).eq("status", value: "live")
            .eq("group_id", value: groupId).or(notExpiredFilter).execute().value
        return try await signFeedPhotos(rows)
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

    // MARK: - Fit-Check detail / voting / comments

    static func fetchFitCheckDetail(id: UUID) async throws -> FitCheckDetailDTO? {
        let rows: [FitCheckDetailDTO] = try await client
            .from("fit_checks")
            .select("id, caption, status, creator_id, expires_at, fit_check_photos(id, fit_check_id, image_url, position), profiles(nickname, avatar_url)")
            .eq("id", value: id)
            .execute()
            .value
        guard var detail = rows.first else { return nil }
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
        // The creator's "someone voted" notification is created by a DB
        // trigger on fit_check_votes (see 0010_db_invariants.sql) — no
        // second write from here.
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

    static func createFitCheck(creatorId: UUID, caption: String?, groupId: UUID?, votingDuration: TimeInterval, photos: [UIImage]) async throws {
        guard photos.count == 2 || photos.count == 4 else { throw APIError.message("Upload exactly 2 or 4 photos.") }
        guard (caption ?? "").count <= 280 else { throw APIError.message("Keep the caption under 280 characters.") }
        let session = try await client.auth.session
        guard creatorId == session.user.id else { throw APIError.message("Please sign in again.") }

        if let groupId {
            let memberships: [GroupMember] = try await client.from("group_members").select()
                .eq("group_id", value: groupId).eq("profile_id", value: creatorId).execute().value
            guard !memberships.isEmpty else { throw APIError.message("You're not a member of that group.") }
        }
        struct DraftParams: Encodable {
            let id: UUID
            let caption: String?
            let groupId: UUID?
            enum CodingKeys: String, CodingKey { case id = "p_id"; case caption = "p_caption"; case groupId = "p_group_id" }
        }
        let fitCheckId: UUID = try await client.rpc("create_fit_check_draft", params: DraftParams(id: UUID(), caption: caption, groupId: groupId)).execute().value
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

    static func fetchGroupMembers(groupId: UUID) async throws -> [AuthorInfo] {
        let rows: [MemberDTO] = try await client
            .from("group_members")
            .select("profiles(nickname, avatar_url)")
            .eq("group_id", value: groupId)
            .execute()
            .value
        return rows.compactMap(\.profiles)
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

    static func blockUser(id: UUID) async throws {
        try await client.rpc("block_user", params: ["p_blocked_id": id]).execute()
    }

    // MARK: - Storage

    // Accept stored paths and legacy public URLs from this project's bucket.
    // Never persist a signed URL: it expires and is specific to a read request.
    private static func photoPath(_ value: String) -> String? {
        if !value.contains("://") { return value.isEmpty ? nil : value }
        guard let url = URL(string: value), url.host == AppConfig.supabaseURL.host else { return nil }
        let prefix = "/storage/v1/object/public/fit-check-photos/"
        guard url.path.hasPrefix(prefix) else { return nil }
        return String(url.path.dropFirst(prefix.count))
    }

    private static func signedPhotoURLs(_ values: [String]) async throws -> [String: String] {
        let paths = Array(Set(values.compactMap(photoPath)))
        guard !paths.isEmpty else { return [:] }
        var signed: [String: String] = [:]
        // Bound each Storage request even for a large account gallery.
        for start in stride(from: 0, to: paths.count, by: 100) {
            let batch = Array(paths[start..<min(start + 100, paths.count)])
            let results: [SignedURLResult] = try await client.storage.from("fit-check-photos")
                .createSignedURLs(paths: batch, expiresIn: 3600)
            for result in results {
                if let url = result.signedURL { signed[result.path] = url.absoluteString }
            }
        }
        return Dictionary(uniqueKeysWithValues: Set(values).compactMap { value in
            guard let path = photoPath(value), let url = signed[path] else { return nil }
            return (value, url)
        })
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

    /// Crops to `aspectRatio` and downscales BEFORE upload, so the stored
    /// image actually matches the grid cell it's displayed in everywhere
    /// (create screen, feed, detail) instead of uploading the original
    /// camera-resolution photo and leaving cropping to whichever view
    /// happens to render it.
    private static func uploadImage(_ image: UIImage, bucket: String, pathPrefix: String, aspectRatio: CGFloat) async throws -> String {
        let prepared = image
            .croppedToAspectRatio(aspectRatio)
            .resized(maxDimension: 1600)

        guard let data = prepared.jpegData(compressionQuality: 0.85) else {
            throw APIError.message("Couldn't process that image.")
        }
        let path = "\(pathPrefix)/\(UUID().storagePathComponent).jpg"
        try await client.storage.from(bucket).upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        return bucket == "fit-check-photos" ? path : try client.storage.from(bucket).getPublicURL(path: path).absoluteString
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
