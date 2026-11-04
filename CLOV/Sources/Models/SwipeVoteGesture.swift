import CoreGraphics

enum SwipeVoteAction: Equatable {
    case vote, nextLook, previousLook, none
}

/// Turns a horizontal drag on a reel page into a vote or a browse action.
enum SwipeVoteGesture {
    /// Horizontal distance, in points, a drag must pass to commit.
    static let commitDistance: CGFloat = 90
    /// A drag counts as horizontal only if it is this much wider than tall,
    /// so vertical paging between Fit-Checks isn't hijacked.
    private static let horizontalDominance: CGFloat = 1.5

    private static func isHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * horizontalDominance
    }

    static func action(for translation: CGSize, canVote: Bool) -> SwipeVoteAction {
        guard isHorizontal(translation), abs(translation.width) >= commitDistance else { return .none }
        if translation.width < 0 { return .nextLook }
        return canVote ? .vote : .previousLook
    }

    /// -1...1 while dragging; 0 for vertical drags. Positive is toward voting.
    static func progress(for translation: CGSize) -> CGFloat {
        guard isHorizontal(translation) else { return 0 }
        return max(-1, min(1, translation.width / commitDistance))
    }

    static func index(after index: Int, count: Int, step: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + step) % count + count) % count
    }
}
