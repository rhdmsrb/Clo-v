import Foundation
import Supabase

/// Pure rules for clearing abandoned drafts.
enum DraftSweep {
    /// Full storage paths for the files found in a draft's folder.
    static func storagePaths(creatorId: UUID, draftId: UUID, fileNames: [String]) -> [String] {
        let folder = "\(creatorId.storagePathComponent)/\(draftId.storagePathComponent)"
        return fileNames
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "\(folder)/\($0)" }
    }
}

extension API {
    private static let fitCheckBucket = "fit-check-photos"

    static func sweepStaleDrafts(creatorId: UUID) async {
#if DEBUG
        if SampleData.isActive { return }
#endif
        await cleanUpDrafts(creatorId: creatorId)
    }

    /// Claim on the server before deleting files so publishing on another
    /// device cannot leave a live post pointing at deleted photos.
    static func cleanUpDrafts(creatorId: UUID, id: UUID? = nil) async {
        struct ClaimedDraft: Decodable { let id: UUID }
        let availability = RuntimeReadAvailability.shared
        guard await availability.shouldTry(.draftCleanup) else { return }
        do {
            guard try await client.auth.session.user.id == creatorId else { return }
            let drafts: [ClaimedDraft]
            if let id {
                drafts = try await client.rpc("claim_fit_check_drafts_for_cleanup_v1", params: ["p_id": id]).execute().value
            } else {
                drafts = try await client.rpc("claim_fit_check_drafts_for_cleanup_v1").execute().value
            }
            for draft in drafts {
                try Task.checkCancellation()
                guard await removeDraftFiles(creatorId: creatorId, draftId: draft.id) else { continue }
                try await client.from("fit_checks").delete()
                    .eq("id", value: draft.id)
                    .eq("creator_id", value: creatorId)
                    .eq("status", value: "draft")
                    .eq("draft_cleanup_claimed", value: true)
                    .execute()
            }
        } catch where isMissingColumnError(error) {
            // Older server: let a safe sweep retry after the migration lands.
            await availability.markUnavailable(.draftCleanup)
        } catch is CancellationError {
            return
        } catch {
            Log.app.error("Draft cleanup failed: \(error.localizedDescription)")
        }
    }

    /// Returns whether the draft's folder is now empty of files.
    private static func removeDraftFiles(creatorId: UUID, draftId: UUID) async -> Bool {
        let folder = "\(creatorId.storagePathComponent)/\(draftId.storagePathComponent)"
        do {
            let bucket = client.storage.from(fitCheckBucket)
            let files = try await bucket.list(path: folder)
            let paths = DraftSweep.storagePaths(creatorId: creatorId, draftId: draftId, fileNames: files.map(\.name))
            if !paths.isEmpty { _ = try await bucket.remove(paths: paths) }
            return true
        } catch {
            Log.storage.error("Draft file sweep failed for \(draftId.uuidString): \(error.localizedDescription)")
            return false
        }
    }
}
