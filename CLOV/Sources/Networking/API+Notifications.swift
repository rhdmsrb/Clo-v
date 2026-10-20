import Foundation
import UIKit
import Supabase

extension API {
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
            await removeStorageFiles(bucket: "fit-check-photos", paths: paths)
        }
    }
}
