import Foundation

/// Description and tags for one photo of a new Fit-Check. Passed per photo
/// (not positionally) so details can never silently shift to another photo.
struct PhotoDetail: Equatable {
    /// Empty means "no description".
    var description = ""
    var tags: [String] = []
}

/// Params of the `create_fit_check_draft` RPC. Optional keys are omitted
/// when nil so an old-style payload (no tags, no vote prompt) still works.
struct DraftParams: Encodable {
    let id: UUID
    let caption: String?
    let groupId: UUID?
    let occasion: String?
    let tags: [String]?
    let votePrompt: String?
    enum CodingKeys: String, CodingKey {
        case id = "p_id", caption = "p_caption", groupId = "p_group_id"
        case occasion = "p_occasion", tags = "p_tags", votePrompt = "p_vote_prompt"
    }
}

/// A `fit_check_photos` row. Description and tags are omitted when nil.
struct PhotoInsert: Encodable {
    let fitCheckId: UUID
    let imageUrl: String
    let position: Int
    let description: String?
    let tags: [String]?
    enum CodingKeys: String, CodingKey {
        case fitCheckId = "fit_check_id", imageUrl = "image_url", position, description, tags
    }
}

/// Cleans user-entered Fit-Check text before any network call, so limits are
/// reported in plain language instead of as Postgres errors after an upload.
enum FitCheckSubmission {
    /// Single source for the post-level and per-photo tag limits (also the wizard's).
    static let maxTags = 8
    static let maxTagLength = 30
    static let maxDescriptionLength = 200
    static let maxVotePromptLength = 120

    /// Trimmed, lowercased, de-duplicated (first wins), each capped at 30 chars.
    /// Throws when more than 8 distinct tags remain.
    static func normalizedTags(_ tags: [String]) throws -> [String] {
        var seen = Set<String>()
        let cleaned = tags.compactMap { raw -> String? in
            let tag = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(maxTagLength))
            guard !tag.isEmpty, seen.insert(tag).inserted else { return nil }
            return tag
        }
        guard cleaned.count <= maxTags else { throw APIError.message("Use at most \(maxTags) tags.") }
        return cleaned
    }

    /// Trimmed and capped at 200 chars; nil when blank.
    static func normalizedDescription(_ text: String?) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxDescriptionLength))
    }

    static func normalizedVotePrompt(_ text: String?) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxVotePromptLength))
    }

    /// One cleaned detail per photo, or empty when none was supplied.
    /// Throws when a non-empty list does not match the photo count.
    static func normalizedDetails(_ details: [PhotoDetail], photoCount: Int) throws -> [PhotoDetail] {
        guard !details.isEmpty else { return [] }
        guard details.count == photoCount else {
            throw APIError.message("Photo details don’t match the photos. Please try again.")
        }
        return try details.map {
            PhotoDetail(description: normalizedDescription($0.description) ?? "", tags: try normalizedTags($0.tags))
        }
    }
}
