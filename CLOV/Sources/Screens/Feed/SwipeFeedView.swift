import SwiftUI

/// An immersive, one-look-at-a-time feed. The regular editorial feed remains
/// useful for scanning; this view provides the fast vertical loop for users
/// who want to browse and vote quickly.
struct SwipeFeedView: View {
    let items: [FeedItemDTO]
    let voterId: UUID
    let followingIDs: Set<UUID>
    let isFollowingMode: Bool
    let isLoading: Bool
    let hasLoaded: Bool
    let error: String?
    let onModeChange: (Bool) -> Void
    let onBrowse: () -> Void
    let onClose: () -> Void
    let onToggleFollow: (UUID, Bool) -> Void
    let onEvent: (FeedItemDTO, String) -> Void
    let onImpression: (FeedItemDTO) -> Void
    let onLoadMore: () -> Void
    let onRefresh: () async -> Void
    let onRetry: () async -> Void

    private static let headerTopPadding: CGFloat = 58
    private static let headerBottomPadding: CGFloat = 12
    /// Leaves room for the close button at the header's leading edge.
    private static let logoLeadingInset: CGFloat = 48
    private static let closeVisualSize: CGFloat = 34
    private static let closeTopPadding: CGFloat = 58
    /// Request the next page when this many pages (or fewer) remain.
    private static let loadMoreLookahead = 3

    @State private var currentItemID: UUID?

    var body: some View {
        ZStack(alignment: .top) {
            content
            header
            closeButton
        }
        .background(.black)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        page(for: item)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $currentItemID)
            .onChange(of: currentItemID) { _, id in loadMoreIfNearEnd(currentID: id) }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .refreshable { await onRefresh() }
        }
    }

    private func page(for item: FeedItemDTO) -> some View {
        SwipeFitCheckPage(
            item: item,
            voterId: voterId,
            isFollowing: followingIDs.contains(item.creatorId),
            onToggleFollow: { onToggleFollow(item.creatorId, $0) },
            onEvent: { onEvent(item, $0) },
            onImpression: { onImpression(item) }
        )
        .containerRelativeFrame(.vertical)
    }

    private func loadMoreIfNearEnd(currentID: UUID?) {
        guard let currentID, let index = items.firstIndex(where: { $0.id == currentID }) else { return }
        if index >= items.count - Self.loadMoreLookahead { onLoadMore() }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isLoading && !hasLoaded {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            errorState(error)
        } else {
            emptyMessage
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") { Task { await onRetry() } }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.white, in: Capsule())
                .disabled(isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(isFollowingMode ? "Your people are getting dressed." : "Your next favorite look is out there.")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(isFollowingMode ? "Follow a few creators to fill this feed." : "Be the first to post a Fit-Check and get the conversation started.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: onBrowse) {
                Label("Explore Fit-Checks", systemImage: "safari")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.white, in: Capsule())
                    .foregroundStyle(.black)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("CLO·V")
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .padding(.leading, Self.logoLeadingInset)
            Spacer(minLength: 8)
            modeButton("For You", selected: !isFollowingMode) { onModeChange(false) }
            modeButton("Following", selected: isFollowingMode) { onModeChange(true) }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, Self.headerTopPadding)
        .padding(.bottom, Self.headerBottomPadding)
        .background(LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
    }

    /// Always-visible way back to the editorial feed. A dark circular
    /// backing keeps it legible over light and dark photos at any size.
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: Self.closeVisualSize, height: Self.closeVisualSize)
                .background(.black.opacity(0.55), in: Circle())
                .frame(minWidth: FeedLayout.minHitSize, minHeight: FeedLayout.minHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .padding(.top, Self.closeTopPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("Close reel")
        .accessibilityIdentifier("closeReelButton")
    }

    private func modeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(selected ? .bold : .medium))
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.72))
                Capsule()
                    .fill(selected ? Theme.accent : .clear)
                    .frame(width: selected ? 28 : 8, height: 3)
                    .accessibilityHidden(true)
            }
            .frame(minWidth: 66, minHeight: FeedLayout.minHitSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum FeedLayout {
    /// Apple HIG minimum tappable size.
    static let minHitSize: CGFloat = 44
}
