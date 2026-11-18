import SwiftUI

/// The Vote tab: a queue of live posts the viewer has not voted on yet, using the
/// same cards and voting as Home. (The full-screen swipe reel, `SwipeFeedView`, is
/// still hidden: its layout is unfinished.)
struct VoteTabView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            FeedView(style: .voteQueue)
        }
        .accessibilityIdentifier("vote.tab")
    }
}
