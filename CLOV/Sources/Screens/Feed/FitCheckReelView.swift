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

    var body: some View {
        VoteFanScreen(item: item, voterId: voterId, isFollowing: isFollowing, initialPhotoIndex: initialPhotoIndex,
                      onToggleFollow: onToggleFollow, onEvent: onEvent, onImpression: onImpression)
            .background(.black)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
    }
}
