import SwiftUI

/// A single Fit-Check shown full screen as a pushed screen with a back button.
struct FitCheckReelView: View {
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
