import Foundation
import Supabase

/// Pure rules for clearing abandoned drafts.
enum DraftSweep {
    /// A post being made is seconds or minutes old, so anything older than this is a leftover
    /// from a crash, a kill mid-upload, or a cleanup that failed.
    static let minimumAge: TimeInterval = 3600
    /// Bounds the work (and network) one sweep does.
    static let maxDraftsPerSweep = 20

    static func cutoff(now: Date) -> Date { now.addingTimeInterval(-minimumAge) }

    static func isStale(createdAt: Date, now: Date) -> Bool { createdAt <= cutoff(now: now) }

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

    /// Removes this user's stale drafts and their stored photos. Best-effort and silent:
    /// a failure leaves the draft for the next sweep. Files go first, so a draft row is
    /// never deleted while its photos remain. Only rows still marked `draft` are touched,
    /// so a published post can never be removed by this.
    static func sweepStaleDrafts(creatorId: UUID, now: Date = Date()) async {
#if DEBUG
        if SampleData.isActive { return }
#endif
        struct DraftRow: Decodable { let id: UUID }
        do {
            let drafts: [DraftRow] = try await client.from("fit_checks").select("id")
                .eq("creator_id", value: creatorId)
                .eq("status", value: "draft")
                .lte("created_at", value: DraftSweep.cutoff(now: now))
                .limit(DraftSweep.maxDraftsPerSweep)
                .execute().value
            for draft in drafts {
                guard await removeDraftFiles(creatorId: creatorId, draftId: draft.id) else { continue }
                try await client.from("fit_checks").delete()
                    .eq("id", value: draft.id)
                    .eq("creator_id", value: creatorId)
                    .eq("status", value: "draft")
                    .execute()
            }
        } catch {
            Log.app.error("Stale draft sweep failed: \(error.localizedDescription)")
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
