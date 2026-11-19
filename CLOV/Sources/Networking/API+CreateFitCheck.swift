import Foundation
import Supabase
import UIKit

/// What happened when a Fit-Check was posted.
struct FitCheckPostResult: Equatable {
    /// True when the server predates migrations 20261107* and the title,
    /// tags or per-photo details had to be left out so the post could go up.
    let droppedExtras: Bool
}

/// What the server holds for a post whose publish call failed.
enum PostServerState: Equatable {
    case live, draft, missing
    /// The status lookup itself failed, so nothing is known.
    case unknown

    /// Any status other than `draft` means the post was published.
    init(status: String) { self = status == "draft" ? .draft : .live }
}

/// What to do with a post after its publish call failed.
enum PublishRecovery: Equatable {
    /// The server already made it live: report success.
    case treatAsPublished
    /// Still a draft, or unknown: keep the draft and photos so a retry can finish it.
    case keepForRetry
    /// The draft row is gone: clean up and start over on the next attempt.
    case discard
}

extension API {
    static func publishRecovery(for state: PostServerState) -> PublishRecovery {
        switch state {
        case .live: .treatAsPublished
        case .draft, .unknown: .keepForRetry
        case .missing: .discard
        }
    }

    /// Looks the post up by id; `.unknown` when the lookup fails. Detached so a
    /// cancelled caller still gets an answer.
    private static func serverState(ofFitCheck id: UUID) async -> PostServerState {
        struct StatusRow: Decodable { let status: String }
        return await Task.detached {
            do {
                let rows: [StatusRow] = try await client.from("fit_checks").select("status")
                    .eq("id", value: id).limit(1).execute().value
                return rows.first.map { PostServerState(status: $0.status) } ?? .missing
            } catch {
                Log.app.error("Post status lookup failed: \(error.localizedDescription)")
                return .unknown
            }
        }.value
    }

    private struct PublishParams: Encodable {
        let id: UUID
        let durationSeconds: Int
        enum CodingKeys: String, CodingKey { case id = "p_id"; case durationSeconds = "p_duration_seconds" }
    }

    /// Everything `createFitCheck` needs after validation, in one value.
    private struct CleanSubmission {
        let tags: [String]
        let details: [PhotoDetail]
        let votePrompt: String?
    }

    /// Drafts, uploads, then publishes. A failure keeps the draft and the photos already
    /// stored: pass the latest `onProgress` value back as `resuming` and only the missing
    /// photos are uploaded. If the caller changed anything meanwhile, the old attempt is
    /// removed and the post starts fresh. `onProgress(nil)` means nothing is left behind.
    /// `onPhotoUploaded` receives the 1-based count of photos stored so far.
    @discardableResult
    static func createFitCheck(creatorId: UUID, caption: String?, occasion: String? = nil, groupId: UUID?, audience: String = "public", votePrompt: String? = nil, votingDuration: TimeInterval, photos: [UIImage], tags: [String] = [], photoDetails: [PhotoDetail] = [], resuming: PostProgress? = nil, onProgress: (@MainActor @Sendable (PostProgress?) -> Void)? = nil, onPhotoUploaded: (@MainActor @Sendable (Int) -> Void)? = nil) async throws -> FitCheckPostResult {
#if DEBUG
        if SampleData.isActive { return FitCheckPostResult(droppedExtras: false) }
#endif
        guard photos.count == 2 || photos.count == 4 else { throw APIError.message("Upload exactly 2 or 4 photos.") }
        guard (caption ?? "").count <= 280 else { throw APIError.message("Keep the caption under 280 characters.") }
        // Validate and clean all text before any network call or slow upload.
        let clean = CleanSubmission(
            tags: try FitCheckSubmission.normalizedTags(tags),
            details: try FitCheckSubmission.normalizedDetails(photoDetails, photoCount: photos.count),
            votePrompt: FitCheckSubmission.normalizedVotePrompt(votePrompt))
        try await validateAudience(creatorId: creatorId, groupId: groupId, audience: audience)

        let prepared = try photos.map { try preparedFitCheckJPEG($0) }
        let photoKeys = prepared.indices.map { PostResume.fingerprint(of: prepared[$0]) + "|" + detailKey(clean.details, at: $0) }
        let draftKey = PostResume.draftFingerprint(caption: caption, occasion: occasion, groupId: groupId,
                                                   tags: clean.tags, votePrompt: clean.votePrompt, audience: audience)
        let draftParams = DraftParams(id: UUID(), caption: caption, groupId: groupId, occasion: occasion,
                                      tags: clean.tags.isEmpty ? nil : clean.tags, votePrompt: clean.votePrompt,
                                      audience: ["friends", "private"].contains(audience) ? audience : nil)
        let start = try await beginAttempt(creatorId: creatorId, resuming: resuming, draftKey: draftKey,
                                           photoKeys: photoKeys, draftParams: draftParams, details: clean.details)
        let progress: PostProgress
        switch start {
        case .published(let result):
            if let onProgress { await onProgress(nil) }
            return result
        case .continuing(let current):
            progress = current
        }
        if let onProgress { await onProgress(progress) }
        let stored = try await storeMissingPhotos(creatorId: creatorId, progress: progress, prepared: prepared,
                                                  photoKeys: photoKeys, details: clean.details,
                                                  onProgress: onProgress, onPhotoUploaded: onPhotoUploaded)
        return try await publishPost(creatorId: creatorId, progress: stored, details: clean.details,
                                     durationSeconds: Int(votingDuration), onProgress: onProgress)
    }

    /// Preserves the selected image (including an optional user crop) during upload.
    static func preparedFitCheckJPEG(_ image: UIImage) throws -> Data {
        try preparedJPEG(image, aspectRatio: 3.0 / 4.0, preserveAspectRatio: true)
    }

    private enum AttemptStart {
        case continuing(PostProgress)
        case published(FitCheckPostResult)
    }

    private static func detailKey(_ details: [PhotoDetail], at index: Int) -> String {
        guard details.indices.contains(index) else { return "" }
        return details[index].description + "\u{1F}" + details[index].tags.joined(separator: ",")
    }

    private static func result(for progress: PostProgress, details: [PhotoDetail]) -> FitCheckPostResult {
        FitCheckPostResult(droppedExtras: progress.draftDropped || (progress.photoExtrasDropped && hasPhotoExtras(details)))
    }

    /// Continues a previous attempt when it still matches, otherwise starts a new draft.
    private static func beginAttempt(creatorId: UUID, resuming: PostProgress?, draftKey: String, photoKeys: [String],
                                     draftParams: DraftParams, details: [PhotoDetail]) async throws -> AttemptStart {
        if let resuming {
            let state = await serverState(ofFitCheck: resuming.draftId)
            switch PostResume.decide(resuming, draftFingerprint: draftKey, photoFingerprints: photoKeys, serverState: state) {
            case .alreadyPublished: return .published(result(for: resuming, details: details))
            case .resume: return .continuing(resuming)
            case .discardThenFresh, .fresh: await discardProgress(creatorId: creatorId, resuming, knownState: state)
            }
        }
        do {
            let (id, dropped) = try await createDraft(draftParams)
            return .continuing(PostProgress(draftId: id, draftFingerprint: draftKey, draftDropped: dropped))
        } catch {
            // The id is generated here so a draft whose response was lost can still be cleaned up.
            await discardDraft(fitCheckId: draftParams.id, creatorId: creatorId)
            throw error
        }
    }

    /// Uploads and records each photo not yet stored. Progress is reported after every
    /// durable step, so a failure at any point leaves an accurate record to resume from.
    private static func storeMissingPhotos(creatorId: UUID, progress start: PostProgress, prepared: [Data], photoKeys: [String],
                                           details: [PhotoDetail], onProgress: (@MainActor @Sendable (PostProgress?) -> Void)?,
                                           onPhotoUploaded: (@MainActor @Sendable (Int) -> Void)?) async throws -> PostProgress {
        var progress = start
        let folder = "\(creatorId.storagePathComponent)/\(progress.draftId.storagePathComponent)"
        for index in prepared.indices {
            if !progress.photos.indices.contains(index) {
                let path = try await uploadJPEG(prepared[index], bucket: "fit-check-photos", pathPrefix: folder)
                progress.photos.append(UploadedPhoto(fingerprint: photoKeys[index], path: path, rowInserted: false))
                if let onProgress { await onProgress(progress) }
            }
            if !progress.photos[index].rowInserted {
                let detail = details.indices.contains(index) ? details[index] : nil
                let insert = PhotoInsert(fitCheckId: progress.draftId, imageUrl: progress.photos[index].path, position: index + 1,
                                         description: detail.flatMap { $0.description.isEmpty ? nil : $0.description },
                                         tags: (detail?.tags ?? []).isEmpty ? nil : detail?.tags)
                do {
                    let dropped = try await insertPhoto(insert, skippingExtras: progress.photoExtrasDropped)
                    progress.photoExtrasDropped = progress.photoExtrasDropped || dropped
                } catch where error.isUniqueViolation {
                    // The row from an earlier attempt landed even though its response was lost.
                }
                progress.photos[index].rowInserted = true
                if let onProgress { await onProgress(progress) }
            }
            if let onPhotoUploaded { await onPhotoUploaded(index + 1) }
        }
        return progress
    }

    /// Publishes the draft. The response can be lost after the server already went live,
    /// so a failure asks the server before deciding what to do with the draft.
    private static func publishPost(creatorId: UUID, progress: PostProgress, details: [PhotoDetail], durationSeconds: Int,
                                    onProgress: (@MainActor @Sendable (PostProgress?) -> Void)?) async throws -> FitCheckPostResult {
        do {
            try await client.rpc("publish_fit_check", params: PublishParams(id: progress.draftId, durationSeconds: durationSeconds)).execute()
        } catch {
            switch publishRecovery(for: await serverState(ofFitCheck: progress.draftId)) {
            case .treatAsPublished:
                Log.app.error("Publish reported \(error.localizedDescription) but \(progress.draftId.uuidString) is live; treating as posted")
            case .keepForRetry:
                Log.app.error("Publish failed; keeping draft \(progress.draftId.uuidString) so a retry can finish it")
                throw error
            case .discard:
                await discardDraft(fitCheckId: progress.draftId, creatorId: creatorId)
                if let onProgress { await onProgress(nil) }
                throw error
            }
        }
        if let onProgress { await onProgress(nil) }
        return result(for: progress, details: details)
    }

    /// Removes an abandoned attempt. Never deletes a post the server has made live, or one
    /// whose state could not be read; the stale-draft sweep handles those later.
    static func discardProgress(creatorId: UUID, _ progress: PostProgress, knownState: PostServerState? = nil) async {
        let state: PostServerState
        if let knownState { state = knownState } else { state = await serverState(ofFitCheck: progress.draftId) }
        switch state {
        case .draft, .missing:
            await discardDraft(fitCheckId: progress.draftId, creatorId: creatorId)
        case .live, .unknown:
            Log.app.error("Leaving \(progress.draftId.uuidString) untouched (\(String(describing: state)))")
        }
    }

    private static func validateAudience(creatorId: UUID, groupId: UUID?, audience: String) async throws {
        let session = try await client.auth.session
        guard creatorId == session.user.id else { throw APIError.message("Please sign in again.") }
        if let groupId {
            let memberships: [GroupMember] = try await client.from("group_members").select()
                .eq("group_id", value: groupId).eq("profile_id", value: creatorId).execute().value
            guard !memberships.isEmpty else { throw APIError.message("You're not a member of that group.") }
        }
        // Server (20261108000100) enforces the same rule: group needs a group id,
        // every other audience must not have one.
        guard ["public", "friends", "group", "private"].contains(audience), (audience == "group") == (groupId != nil) else {
            throw APIError.message("Choose a valid audience for this Fit-Check.")
        }
    }

    /// Creates the draft. If the server lacks the p_tags / p_vote_prompt
    /// overload (PGRST202), retries once without them. Returns whether it did.
    private static func createDraft(_ params: DraftParams) async throws -> (id: UUID, droppedExtras: Bool) {
        do {
            let id: UUID = try await client.rpc("create_fit_check_draft", params: params).execute().value
            return (id, false)
        } catch where isMissingColumnError(error) && hasDraftExtras(params) {
            Log.app.error("create_fit_check_draft lacks tags/vote prompt; retrying without: \(error.localizedDescription)")
            let plain = DraftParams(id: params.id, caption: params.caption, groupId: params.groupId,
                                    occasion: params.occasion, tags: nil, votePrompt: nil,
                                    audience: params.audience)  // never dropped: it would widen visibility
            let id: UUID = try await client.rpc("create_fit_check_draft", params: plain).execute().value
            return (id, true)
        }
    }

    /// Inserts one photo row. If the description/tags columns are missing,
    /// retries once without them. Returns whether extras were dropped.
    private static func insertPhoto(_ insert: PhotoInsert, skippingExtras: Bool) async throws -> Bool {
        let plain = PhotoInsert(fitCheckId: insert.fitCheckId, imageUrl: insert.imageUrl, position: insert.position, description: nil, tags: nil)
        guard !skippingExtras else {
            try await client.from("fit_check_photos").insert(plain).execute()
            return true
        }
        do {
            try await client.from("fit_check_photos").insert(insert).execute()
            return false
        } catch where isMissingColumnError(error) && (insert.description != nil || insert.tags != nil) {
            Log.app.error("fit_check_photos lacks description/tags; retrying without: \(error.localizedDescription)")
            try await client.from("fit_check_photos").insert(plain).execute()
            return true
        }
    }

    private static func hasDraftExtras(_ params: DraftParams) -> Bool {
        params.tags != nil || params.votePrompt != nil
    }

    private static func hasPhotoExtras(_ details: [PhotoDetail]) -> Bool {
        details.contains { !$0.description.isEmpty || !$0.tags.isEmpty }
    }
}
