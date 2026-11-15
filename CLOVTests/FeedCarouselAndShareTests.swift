import CoreGraphics
import Foundation
import Testing
@testable import CLOV

struct FeedCarouselAndShareTests {
    @Test("Resizing keeps index in range and the stopped flag")
    func resizeClampsAndKeepsStopped() {
        let logic = CarouselAutoAdvance(pageCount: 4, index: 3).userInteracted().resized(pageCount: 2)
        #expect(logic.pageCount == 2)
        #expect(logic.index == 1)
        #expect(logic.isStopped)
    }

    @Test("Growing from zero pages makes rotation possible")
    func resizeFromEmpty() {
        let logic = CarouselAutoAdvance(pageCount: 0).resized(pageCount: 3)
        #expect(logic.shouldRun(enabled: true, reduceMotion: false, isOnScreen: true))
    }

    @Test("Only mostly-horizontal drags count as a swipe", arguments: [
        (CGSize(width: 30, height: 4), true),
        (CGSize(width: -30, height: 4), true),
        (CGSize(width: 3, height: 40), false),
        (CGSize(width: 12, height: 40), false),
        (CGSize(width: 5, height: 0), false)
    ])
    func horizontalSwipe(translation: CGSize, expected: Bool) {
        #expect(CarouselAutoAdvance.isHorizontalSwipe(translation) == expected)
    }

    @Test("Share text falls back to plain text without a link")
    func shareTextWithoutURL() {
        #expect(PostCardContent.shareText(title: "Date night", url: nil)
            == "Date night\n\nCheck out this Fit-Check on CLO·V")
    }

    @Test("Share text includes the link when available")
    func shareTextWithURL() throws {
        let url = try #require(URL(string: "https://example.com/vote/abc"))
        #expect(PostCardContent.shareText(title: "Date night", url: url)
            == "Date night\n\nVote on CLO·V: https://example.com/vote/abc")
    }
}
