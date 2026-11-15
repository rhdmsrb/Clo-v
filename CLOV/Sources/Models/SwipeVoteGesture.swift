/// Pure helpers for browsing a reel's looks by swiping.
enum SwipeVoteGesture {
    static func index(after index: Int, count: Int, step: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + step) % count + count) % count
    }
}
