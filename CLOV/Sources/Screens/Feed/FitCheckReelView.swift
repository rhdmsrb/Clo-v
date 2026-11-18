import SwiftUI

/// A single Fit-Check shown full screen as a pushed screen with a back button.
///
/// Hidden for now: with `isEnabled` false, every route that would open this screen (group posts,
/// Search, `clov://vote/` links) shows the post as the feed card instead, and tapping a card's photo
/// does nothing. Set it to true to bring the screen back.
struct FitCheckReelView: View {
    /// Keep the reel available to offline UI tests while it is hidden in the app.
    static let isEnabled: Bool = {
        #if DEBUG
        SampleData.isActive && ProcessInfo.processInfo.arguments.contains("--uiTestEnableFitCheckReel")
        #else
        false
        #endif
    }()

    let item: FeedItemDTO
    let voterId: UUID
    let isFollowing: Bool
    var initialPhotoIndex: Int? = nil
    let onToggleFollow: (Bool) -> Void
    var onEvent: (String) -> Void = { _ in }
    var onImpression: () -> Void = {}
    var onVoteChange: ((UUID?, Int) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.setTabBarHidden) private var setTabBarHidden

    var body: some View {
        if Self.isEnabled {
            reel
        } else {
            FitCheckDetailView(fitCheckId: item.id)
        }
    }

    private var reel: some View {
        SwipeFitCheckPage(item: item, voterId: voterId, isFollowing: isFollowing,
                          initialPhotoIndex: initialPhotoIndex, onToggleFollow: onToggleFollow,
                          onEvent: onEvent, onImpression: onImpression, onVoteChange: onVoteChange)
            .background(.black)
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(Theme.bodyEmphasis)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier("reelBackButton")
                .padding(.leading, 16)
                .padding(.top, 8)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("voteFanScreen")
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .onAppear { setTabBarHidden(true) }
            .onDisappear { setTabBarHidden(false) }
    }
}
