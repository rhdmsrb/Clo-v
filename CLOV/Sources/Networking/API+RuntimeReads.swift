import Foundation
import Supabase

/// Retry the new reads periodically so a server migration can take effect
/// during a running session. Other errors still reach the screen's retry UI.
actor RuntimeReadAvailability {
    static let shared = RuntimeReadAvailability()

    enum Endpoint { case homeFeed, groupPreviews, draftCleanup }

    private let clock = ContinuousClock()
    private var retryAt: [Endpoint: ContinuousClock.Instant] = [:]

    func shouldTry(_ endpoint: Endpoint) -> Bool {
        retryAt[endpoint].map { $0 <= clock.now } ?? true
    }

    func markUnavailable(_ endpoint: Endpoint) {
        retryAt[endpoint] = clock.now + .seconds(60)
    }
}

extension API {
    struct HomeFeedCursor {
        let createdAt: String
        let id: UUID
    }

    struct HomeFeedPage {
        let items: [FeedItemDTO]
        let nextCursor: HomeFeedCursor?
        let followedAuthors: Set<UUID>
        let likedPosts: Set<UUID>
        let answeredPosts: Set<UUID>
        let scores: [UUID: Int]
    }

    private struct HomeFeedRow: Decodable {
        let cursorCreatedAt: String
        let viewerFollows: Bool
        let viewerLiked: Bool
        let signalScore: Int
        let item: FeedItemDTO
    }

    static func fetchHomeFeedPage(after cursor: HomeFeedCursor? = nil, limit: Int) async throws -> HomeFeedPage? {
#if DEBUG
        if SampleData.isActive { return nil }
#endif
        let availability = RuntimeReadAvailability.shared
        if cursor == nil {
            guard await availability.shouldTry(.homeFeed) else { return nil }
        }
        struct Params: Encodable {
            let pLimit: Int
            let pBeforeCreatedAt: String?
            let pBeforeId: UUID?
        }
        let rows: [HomeFeedRow]
        do {
            rows = try await client.rpc("home_feed_page_v1", params: Params(
                pLimit: limit, pBeforeCreatedAt: cursor?.createdAt, pBeforeId: cursor?.id
            )).execute().value
        } catch where cursor == nil && isMissingColumnError(error) {
            await availability.markUnavailable(.homeFeed)
            return nil
        }
        let items = try await signFeedPhotos(rows.map(\.item), requireBatchSuccess: true)
        let next = rows.count == limit ? rows.last.map {
            HomeFeedCursor(createdAt: $0.cursorCreatedAt, id: $0.item.id)
        } : nil
        return HomeFeedPage(
            items: items,
            nextCursor: next,
            followedAuthors: Set(rows.filter(\.viewerFollows).map(\.item.creatorId)),
            likedPosts: Set(rows.filter(\.viewerLiked).map(\.item.id)),
            answeredPosts: Set(rows.filter { !$0.item.fitCheckVotes.isEmpty }.map(\.item.id)),
            scores: Dictionary(uniqueKeysWithValues: rows.map { ($0.item.id, $0.signalScore) })
        )
    }
}
