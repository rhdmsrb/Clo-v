import Testing
import Foundation
@testable import CLOV

struct HomeFeedFiltersTests {
    private let alice = UUID()
    private let bob = UUID()

    private func item(creator: UUID, hoursAgo: Double, tags: [String]? = nil, occasion: String? = nil) -> FeedItemDTO {
        FeedItemDTO(id: UUID(), creatorId: creator, caption: nil, occasion: occasion, audience: "public",
                    votePrompt: nil, createdAt: Date().addingTimeInterval(-hoursAgo * 3_600),
                    expiresAt: nil, fitCheckPhotos: [], fitCheckVotes: [], fitCheckComments: [],
                    profiles: nil, isPublic: true, tags: tags, likeCount: nil)
    }

    @Test("Options are Popular, New, Following, then the viewer's styles without duplicates")
    func optionsIncludeStylePreferences() {
        let ids = HomeFeedFilters.options(stylePreferences: ["Streetwear", "Minimalist", "streetwear", " "]).map(\.id)
        #expect(ids == ["popular", "new", "following", "tag:streetwear", "tag:minimalist"])
    }

    @Test("Popular keeps the ranked order")
    func popularKeepsOrder() {
        let ranked = [item(creator: alice, hoursAgo: 5), item(creator: bob, hoursAgo: 1)]
        #expect(HomeFeedFilters.apply("popular", to: ranked, followingIDs: []).map(\.id) == ranked.map(\.id))
    }

    @Test("New sorts newest first")
    func newSortsByDate() {
        let old = item(creator: alice, hoursAgo: 5)
        let fresh = item(creator: bob, hoursAgo: 1)
        #expect(HomeFeedFilters.apply("new", to: [old, fresh], followingIDs: []).map(\.id) == [fresh.id, old.id])
    }

    @Test("Following keeps only followed creators")
    func followingFilters() {
        let mine = item(creator: alice, hoursAgo: 1)
        let other = item(creator: bob, hoursAgo: 1)
        #expect(HomeFeedFilters.apply("following", to: [mine, other], followingIDs: [alice]).map(\.id) == [mine.id])
    }

    @Test("A style tag matches post tags or the occasion, ignoring case and #")
    func tagMatches() {
        let tagged = item(creator: alice, hoursAgo: 1, tags: ["#StreetWear"])
        let byOccasion = item(creator: bob, hoursAgo: 2, occasion: "Streetwear, Campus")
        let neither = item(creator: bob, hoursAgo: 3, tags: ["formal"])
        let result = HomeFeedFilters.apply("tag:streetwear", to: [tagged, byOccasion, neither], followingIDs: [])
        #expect(result.map(\.id) == [tagged.id, byOccasion.id])
    }

    @Test("An unknown filter falls back to Popular")
    func unknownFallsBack() {
        let ranked = [item(creator: alice, hoursAgo: 1)]
        #expect(HomeFeedFilters.apply("nonsense", to: ranked, followingIDs: []).count == 1)
    }
}
