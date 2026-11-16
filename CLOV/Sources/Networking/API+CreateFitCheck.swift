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
    case treatAsPublished, discard, leaveUntouched
}

extension API {
    static func publishRecovery(for state: PostServerState) -> PublishRecovery {
        switch state {
        case .live: .treatAsPublished
        case .draft, .missing: .discard
        case .unknown: .leaveUntouched
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

    /// Drafts, uploads, then publishes. On any failure the draft and uploaded
    /// photos are removed so a retry never leaves a live half-post.
    /// `onPhotoUploaded` receives the 1-based count of photos stored so far.
    @discardableResult
    static func createFitCheck(creatorId: UUID, caption: String?, occasion: String? = nil, groupId: UUID?, audience: String = "public", votePrompt: String? = nil, votingDuration: TimeInterval, photos: [UIImage], tags: [String] = [], photoDetails: [PhotoDetail] = [], onPhotoUploaded: (@MainActor @Sendable (Int) -> Void)? = nil) async throws -> FitCheckPostResult {
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

        // The id is generated here so a draft whose response was lost can still be cleaned up.
        let draftParams = DraftParams(id: UUID(), caption: caption, groupId: groupId, occasion: occasion,
                                      tags: clean.tags.isEmpty ? nil : clean.tags, votePrompt: clean.votePrompt,
                                      audience: ["friends", "private"].contains(audience) ? audience : nil)
        let fitCheckId: UUID
        let draftDropped: Bool
        do {
            (fitCheckId, draftDropped) = try await createDraft(draftParams)
        } catch {
            await discardDraft(fitCheckId: draftParams.id, creatorId: creatorId, uploadedPaths: [])
            throw error
        }
        var uploadedPaths: [String] = []
        var publishStarted = false
        var photoExtrasDropped = false
        do {
            for (index, photo) in photos.enumerated() {
                let path = try await uploadImage(photo, bucket: "fit-check-photos", pathPrefix: "\(creatorId.storagePathComponent)/\(fitCheckId.storagePathComponent)", aspectRatio: 3.0 / 4.0)
                uploadedPaths.append(path)
                let detail = clean.details.indices.contains(index) ? clean.details[index] : nil
                let insert = PhotoInsert(fitCheckId: fitCheckId, imageUrl: path, position: index + 1,
                                         description: detail.flatMap { $0.description.isEmpty ? nil : $0.description },
                                         tags: (detail?.tags ?? []).isEmpty ? nil : detail?.tags)
                photoExtrasDropped = try await insertPhoto(insert, skippingExtras: photoExtrasDropped) || photoExtrasDropped
                if let onPhotoUploaded { await onPhotoUploaded(index + 1) }
            }
            publishStarted = true
            try await client.rpc("publish_fit_check", params: PublishParams(id: fitCheckId, durationSeconds: Int(votingDuration))).execute()
        } catch {
            // Once publishing started, the server may have gone live even though the
            // response was lost (timeout, dropped signal, cancellation). Deleting a
            // live post is irreversible, so ask the server before discarding.
            if publishStarted {
                let state = await serverState(ofFitCheck: fitCheckId)
                switch publishRecovery(for: state) {
                case .treatAsPublished:
                    Log.app.error("Publish reported \(error.localizedDescription) but \(fitCheckId.uuidString) is live; treating as posted")
                    return FitCheckPostResult(droppedExtras: draftDropped || (photoExtrasDropped && hasPhotoExtras(clean.details)))
                case .leaveUntouched:
                    Log.app.error("Publish failed and post state is unknown; leaving \(fitCheckId.uuidString) untouched")
                    throw error
                case .discard:
                    break
                }
            }
            await discardDraft(fitCheckId: fitCheckId, creatorId: creatorId, uploadedPaths: uploadedPaths)
            throw error
        }
        return FitCheckPostResult(droppedExtras: draftDropped || (photoExtrasDropped && hasPhotoExtras(clean.details)))
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
