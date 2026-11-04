import Foundation
import Supabase

extension API {
    private struct PopularParams: Encodable {
        let pLimit: Int
        let pOffset: Int
        let pWindowDays: Int
    }

    private struct PopularRow: Decodable {
        let id: UUID
    }

    /// Popular public Fit-Checks from the last `windowDays` days, most voted
    /// and discussed first. Meant as the cold-start feed when a new user has no
    /// friends or follows. Requires migration 20261102000300.
    static func fetchPopularFeed(offset: Int, limit: Int, windowDays: Int = 7) async throws -> FeedPageResult {
#if DEBUG
        if SampleData.isActive {
            return SampleData.feedPage(offset: offset, limit: limit, search: "", occasion: nil, followingIDs: nil)
        }
#endif
        let ranked: [PopularRow] = try await client
            .rpc("popular_fit_checks", params: PopularParams(pLimit: limit, pOffset: offset, pWindowDays: windowDays))
            .execute().value
        guard !ranked.isEmpty else { return FeedPageResult(items: [], fetchedCount: 0) }

        let rows: [FeedItemDTO] = try await client.from("fit_checks")
            .select(feedColumns)
            .in("id", values: ranked.map(\.id))
            .execute().value
        // The IN query has no order; restore the server's popularity order.
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        let ordered = ranked.compactMap { byID[$0.id] }

        let blocked = try await fetchBlockedUserIDs()
        let withPrompts = await attachVotePrompts(ordered)
        let visible = try await signFeedPhotos(withPrompts.filter { !blocked.contains($0.creatorId) })
        return FeedPageResult(items: visible, fetchedCount: ranked.count)
    }
}
