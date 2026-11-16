import CryptoKit
import Foundation

/// One photo of a post that is already in storage.
struct UploadedPhoto: Equatable {
    /// Hash of the bytes that were uploaded, to tell whether the slot still holds the same photo.
    let fingerprint: String
    let path: String
    /// False when the file is stored but its `fit_check_photos` row is not yet written.
    var rowInserted: Bool
}

/// What a failed post left behind, so a retry can continue instead of starting over.
struct PostProgress: Equatable {
    let draftId: UUID
    let draftFingerprint: String
    /// The server lacked the title/tags columns when the draft was created.
    var draftDropped: Bool
    var photoExtrasDropped = false
    var photos: [UploadedPhoto] = []

    var uploadedPaths: [String] { photos.map(\.path) }
}

enum ResumeDecision: Equatable {
    /// Nothing to continue.
    case fresh
    /// Same draft, same photos so far: upload only what is missing.
    case resume
    /// The user changed something (or the draft is gone): remove the old attempt first.
    case discardThenFresh
    /// The previous attempt's publish actually went through.
    case alreadyPublished
}

enum PostResume {
    static func decide(_ progress: PostProgress?, draftFingerprint: String,
                       photoFingerprints: [String], serverState: PostServerState) -> ResumeDecision {
        guard let progress else { return .fresh }
        switch serverState {
        case .live: return .alreadyPublished
        case .missing: return .discardThenFresh
        case .draft, .unknown: break
        }
        let photosMatch = progress.photos.count <= photoFingerprints.count
            && zip(progress.photos, photoFingerprints).allSatisfy { $0.fingerprint == $1 }
        return progress.draftFingerprint == draftFingerprint && photosMatch ? .resume : .discardThenFresh
    }

    static func fingerprint(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Everything the draft RPC stores, so a retry only reuses a draft that still matches.
    static func draftFingerprint(caption: String?, occasion: String?, groupId: UUID?, tags: [String],
                                 votePrompt: String?, audience: String) -> String {
        let parts: [String] = [caption ?? "", occasion ?? "", groupId?.uuidString ?? "",
                               tags.joined(separator: "\u{1F}"), votePrompt ?? "", audience]
        return parts.joined(separator: "\u{1E}")
    }
}
