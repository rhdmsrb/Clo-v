import Foundation
import Testing
@testable import CLOV

struct FeedPostAndExploreLogicTests {
    @Test func titlePrefersPromptThenOccasionThenFallback() {
        #expect(PostCardContent.title(votePrompt: " Which one? ", occasion: "Work") == "Which one?")
        #expect(PostCardContent.title(votePrompt: "  ", occasion: "Work") == "Work")
        #expect(PostCardContent.title(votePrompt: nil, occasion: nil) == PostCardContent.fallbackTitle)
    }

    @Test func photoURLsFollowPositionAndDropInvalid() {
        let photos = [
            FitCheckPhoto(id: UUID(), fitCheckId: nil, imageUrl: "https://x.test/b.jpg", position: 1),
            FitCheckPhoto(id: UUID(), fitCheckId: nil, imageUrl: "https://x.test/a.jpg", position: 0),
            FitCheckPhoto(id: UUID(), fitCheckId: nil, imageUrl: "not a url", position: 2)
        ]
        #expect(PostCardContent.photoURLs(photos).map(\.lastPathComponent) == ["a.jpg", "b.jpg"])
    }

    @Test func defaultFilterIsDefaultAndCountsActive() {
        #expect(ExploreFilter().isDefault)
        #expect(ExploreFilter(occasion: "Work", sort: .mostVoted).activeCount == 2)
    }
}
