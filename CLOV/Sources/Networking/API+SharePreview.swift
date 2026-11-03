import Foundation
import Supabase

/// Public preview of a shared Fit-Check, served by the `fit-check-preview`
/// Edge Function. It carries no user ids or voter details.
struct SharedFitCheckPreview: Decodable, Equatable {
    struct Photo: Decodable, Equatable {
        let position: Int
        let url: URL
    }

    let id: UUID
    let caption: String?
    let occasion: String?
    /// ISO-8601 string as sent by the server; nil when the post never expires.
    let expiresAt: String?
    let authorNickname: String?
    let voteCount: Int
    let commentCount: Int
    let photos: [Photo]
}

private struct PreviewRequest: Encodable {
    let id: String
}

private struct PreviewError: Decodable {
    let message: String?
}

extension API {
    /// Loads the public preview for a share link. Works without a signed-in
    /// session. Throws `APIError.message` with a user-facing reason when the
    /// post is private, expired or missing.
    static func fetchSharedPreview(fitCheckId: UUID) async throws -> SharedFitCheckPreview {
        do {
            return try await client.functions.invoke(
                "fit-check-preview",
                options: FunctionInvokeOptions(body: PreviewRequest(id: fitCheckId.storagePathComponent))
            )
        } catch let error as FunctionsError {
            if case let .httpError(_, data) = error,
               let response = try? JSONDecoder().decode(PreviewError.self, from: data),
               let message = response.message {
                throw APIError.message(message)
            }
            throw APIError.message("Couldn't load this post. Please try again.")
        }
    }
}
