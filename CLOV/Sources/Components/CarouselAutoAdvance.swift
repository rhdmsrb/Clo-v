import CoreGraphics
import Foundation

/// Pure auto-advance rules for `PhotoCarousel`. Value type, every transition
/// returns a new copy, so the logic is testable without a view.
struct CarouselAutoAdvance: Equatable {
    /// Seconds between automatic page changes.
    static let interval: TimeInterval = 3

    let pageCount: Int
    private(set) var index: Int
    /// Set once on first touch/swipe/hold; never cleared for this instance.
    private(set) var isStopped: Bool

    init(pageCount: Int, index: Int = 0, isStopped: Bool = false) {
        self.pageCount = max(pageCount, 0)
        self.index = Self.clamp(index, count: max(pageCount, 0))
        self.isStopped = isStopped
    }

    /// Whether a timer should be running right now. Never while Reduce Motion
    /// is on, or while VoiceOver / Switch Control drive the screen: they step
    /// through photos deliberately and must not have pages change under them.
    func shouldRun(enabled: Bool, reduceMotion: Bool, isOnScreen: Bool, assistiveTechActive: Bool = false) -> Bool {
        enabled && !reduceMotion && !assistiveTechActive && isOnScreen && !isStopped && pageCount > 1
    }

    /// Timer fired: next page, wrapping to the first. No-op once stopped.
    func advanced() -> CarouselAutoAdvance {
        guard !isStopped, pageCount > 1 else { return self }
        return CarouselAutoAdvance(pageCount: pageCount, index: (index + 1) % pageCount, isStopped: false)
    }

    /// Any user interaction permanently stops auto-advance.
    func userInteracted() -> CarouselAutoAdvance {
        CarouselAutoAdvance(pageCount: pageCount, index: index, isStopped: true)
    }

    /// Page changed externally (swipe or binding). Keeps the stopped flag.
    func moved(to newIndex: Int) -> CarouselAutoAdvance {
        CarouselAutoAdvance(pageCount: pageCount, index: newIndex, isStopped: isStopped)
    }

    /// The page count changed (photos loaded or replaced). Keeps the index in
    /// range and the stopped flag.
    func resized(pageCount newCount: Int) -> CarouselAutoAdvance {
        CarouselAutoAdvance(pageCount: newCount, index: index, isStopped: isStopped)
    }

    /// Minimum travel before a drag counts as a swipe rather than a touch.
    static let swipeThreshold: CGFloat = 10

    /// A drag that is mostly horizontal and long enough to be a page swipe.
    /// Vertical drags are the feed scrolling past the card and must not count
    /// as interaction.
    static func isHorizontalSwipe(_ translation: CGSize) -> Bool {
        abs(translation.width) >= swipeThreshold && abs(translation.width) > abs(translation.height)
    }

    private static func clamp(_ value: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(value, 0), count - 1)
    }
}
