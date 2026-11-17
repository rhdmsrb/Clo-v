@preconcurrency import SwiftUI

/// A post opened from a profile tile, shown as the same card the feed uses (photos, vote
/// by pressing the photo, like, comment, send) instead of jumping straight to the vote screen.
/// Posts that can't be shown as a card (gone, draft, blocked, load failure) fall back to
/// `FitCheckDetailView`, which owns those states.
struct ProfilePostView: View {
    let fitCheckId: UUID

    @EnvironmentObject private var appState: AppState

    private enum Phase {
        case loading
        case post(FeedItemDTO)
        case fallback
    }

    @State private var phase: Phase = .loading
    @State private var isLiked = false
    @State private var isFollowing = false
    @State private var commentItem: FeedItemDTO?
    @State private var openedRoute: FitCheckRoute?

    private static let verticalPadding: CGFloat = 12

    var body: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .task(id: fitCheckId) { await load() }
        case .post(let item):
            postScreen(item)
        case .fallback:
            FitCheckDetailView(fitCheckId: fitCheckId)
        }
    }

    private func postScreen(_ item: FeedItemDTO) -> some View {
        ScrollView {
            FeedPostCard(
                item: item,
                isLiked: isLiked,
                viewerId: appState.userId,
                isFollowing: isFollowing,
                showsFollow: item.creatorId != appState.userId,
                onToggleFollow: { setFollowing($0, creatorId: item.creatorId) },
                onLike: { try await setLiked($0, item: item) },
                onOpen: { openedRoute = FitCheckRoute(id: item.id, photoIndex: $0) },
                onComment: { commentItem = item },
                onVoteChange: { applyVote($0, to: item) }
            )
            .padding(.vertical, Self.verticalPadding)
        }
        .clearsTabBar()
        .background(Theme.background)
        .accessibilityIdentifier("profilePost.root")
        .navigationDestination(item: $openedRoute) { FitCheckVoteLoader(fitCheckId: $0.id) }
        .sheet(item: $commentItem) { item in
            CommentThreadSheet(fitCheckId: item.id,
                               photoURLs: PostCardContent.photoURLs(item.fitCheckPhotos).map(\.absoluteString),
                               voterId: appState.userId, canComment: !isExpired(item.expiresAt))
        }
    }

    private func load() async {
        let item: FeedItemDTO?
        do {
            item = try await API.fetchFeedItem(id: fitCheckId)
        } catch {
            Log.app.error("ProfilePostView load failed: \(error.localizedDescription)")
            phase = .fallback
            return
        }
        guard let item else {
            phase = .fallback
            return
        }
        async let liked = Log.attempt("Load liked post") {
            try await API.fetchLikedFitCheckIDs(among: [item.id], userId: appState.userId)
        }
        async let following = Log.attempt("Load following") {
            try await API.fetchFollowingIDs(userId: appState.userId)
        }
        isLiked = await liked?.contains(item.id) ?? false
        isFollowing = await following?.contains(item.creatorId) ?? false
        phase = .post(item)
    }

    /// Throws so `LikeButton` can roll back its optimistic state.
    private func setLiked(_ like: Bool, item: FeedItemDTO) async throws {
        if like {
            try await API.likeFitCheck(id: item.id, userId: appState.userId)
        } else {
            try await API.unlikeFitCheck(id: item.id, userId: appState.userId)
        }
        isLiked = like
    }

    private func setFollowing(_ follow: Bool, creatorId: UUID) {
        isFollowing = follow
        Task {
            do {
                try await API.setFollowing(follow, followerId: appState.userId, followingId: creatorId)
            } catch {
                Log.app.error("Follow toggle failed: \(error.localizedDescription)")
                isFollowing = !follow
            }
        }
    }

    /// Keeps this copy of the post in step with a vote cast on its card.
    private func applyVote(_ photoId: UUID?, to item: FeedItemDTO) {
        phase = .post(PostCardContent.applyingVote(photoId, voterId: appState.userId, to: item))
    }
}
