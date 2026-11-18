import Testing
import Foundation
@testable import CLOV

struct EditorialComponentsTests {
    // MARK: CountdownText

    static let countdownCases: [(Double, String)] = [
        (172_805, "ends in 2d"),
        (18_059, "ends in 5h"),
        (750, "ends in 12m"),
        (30, "ends in <1m"),
        (0, "Ended"),
        (-120, "Ended")
    ]

    @Test("Countdown wording picks the largest whole unit", arguments: countdownCases)
    func countdownLabel(remaining: Double, expected: String) {
        #expect(CountdownText.label(remaining: remaining) == expected)
    }

    @Test("Countdown speaks whole words, not abbreviations")
    func countdownAccessibility() {
        #expect(CountdownText.accessibilityLabel(remaining: 5 * 3_600) == "Voting ends in 5 hours")
        #expect(CountdownText.accessibilityLabel(remaining: -1) == "Voting ended")
    }

    // MARK: FitCardContent

    private func item(occasion: String? = "  Date night ", votePrompt: String? = "Which one?",
                      tags: [String]? = ["minimal", " ", "black", "street", "y2k"]) -> FeedItemDTO {
        let id = UUID()
        let photos = (1...2).map { position in
            FitCheckPhoto(id: UUID(), fitCheckId: id, imageUrl: "https://example.com/\(position).jpg",
                          position: position, description: nil)
        }
        return FeedItemDTO(id: id, creatorId: UUID(), caption: "caption", occasion: occasion,
                           audience: "public", votePrompt: votePrompt, createdAt: .now,
                           expiresAt: .now.addingTimeInterval(3_600), fitCheckPhotos: photos,
                           fitCheckVotes: [], fitCheckComments: [], profiles: nil, isPublic: true,
                           tags: tags, likeCount: nil)
    }

    @Test("Card content trims the occasion and caps tags at three")
    func cardContentMapping() {
        let content = FitCardContent(item: item(), photoIndex: 1, revealsVotes: false)
        #expect(content.occasion == "Date night")
        #expect(content.title == "Which one?")
        #expect(content.tags == ["#minimal", "#black", "#street"])
        #expect(content.photoURL?.absoluteString == "https://example.com/2.jpg")
        #expect(content.username == "Someone")
    }

    @Test("Vote total stays hidden until votes are revealed")
    func cardHidesVotesBeforeReveal() {
        #expect(FitCardContent(item: item(), photoIndex: 0, revealsVotes: false).voteCount == nil)
        #expect(FitCardContent(item: item(), photoIndex: 0, revealsVotes: true).voteCount == 0)
    }

    @Test("A blank occasion is dropped and the title falls back to Fit-Check")
    func cardFallbacks() {
        let content = FitCardContent(item: item(occasion: "  ", votePrompt: nil), photoIndex: 9, revealsVotes: false)
        #expect(content.occasion == nil)
        #expect(content.title == PostCardContent.fallbackTitle)
        #expect(content.photoURL?.absoluteString == "https://example.com/1.jpg")
    }
}
