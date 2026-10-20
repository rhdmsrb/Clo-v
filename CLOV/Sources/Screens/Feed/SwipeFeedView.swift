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
    let onToggleFollow: (UUID, Bool) -> Void
    let onEvent: (FeedItemDTO, String) -> Void
    let onImpression: (FeedItemDTO) -> Void
    let onLoadMore: () -> Void
    let onRefresh: () async -> Void
    let onRetry: () async -> Void

    private static let headerTopPadding: CGFloat = 58
    private static let headerBottomPadding: CGFloat = 12
    /// Request the next page when this many pages (or fewer) remain.
    private static let loadMoreLookahead = 3

    @State private var currentItemID: UUID?

    var body: some View {
        ZStack(alignment: .top) {
            content
            header
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

struct SwipeFitCheckPage: View {
    let item: FeedItemDTO
    let voterId: UUID
    let isFollowing: Bool
    let onToggleFollow: (Bool) -> Void
    let onEvent: (String) -> Void
    let onImpression: () -> Void

    private static let bottomInset: CGFloat = 112

    private var photo: FitCheckPhoto? { item.fitCheckPhotos.sorted { $0.position < $1.position }.first }
    private var nickname: String { item.profiles?.nickname ?? "Someone" }
    private var canFollow: Bool { item.creatorId != voterId }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                background(size: proxy.size)
                Theme.photoScrim
                HStack(alignment: .bottom, spacing: 18) {
                    infoColumn
                    actionRail
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.bottom, Self.bottomInset)
            }
            .contentShape(Rectangle())
            .onAppear(perform: onImpression)
        }
    }

    @ViewBuilder
    private func background(size: CGSize) -> some View {
        if let photo {
            RemoteImage(url: photo.imageUrl, label: "Photo by \(nickname)")
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            Theme.muted
        }
    }

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Text("@\(nickname)")
                    .font(.subheadline.weight(.bold))
                if canFollow { followPill }
            }
            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(3)
            }
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .accessibilityHidden(true)
                Text("CLO·V STYLE CHECK  ·  \((item.occasion ?? "STYLE").uppercased())")
                    .lineLimit(1)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white.opacity(0.88))

            detailLink {
                Label("Vote on the looks", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.18), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var followPill: some View {
        Button(isFollowing ? "Following" : "+ Follow") {
            onToggleFollow(!isFollowing)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(isFollowing ? Color.white : Theme.accentForeground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isFollowing ? .white.opacity(0.18) : Theme.accent, in: Capsule())
        .frame(minHeight: FeedLayout.minHitSize)
        .contentShape(Rectangle())
        .accessibilityLabel("Follow \(nickname)")
        .accessibilityValue(isFollowing ? "Following" : "Not following")
        .accessibilityAddTraits(.isToggle)
    }

    private var actionRail: some View {
        VStack(spacing: 18) {
            avatarButton
            detailLink { feedAction("heart.fill", count: item.fitCheckVotes.count, label: "Vote") }
            detailLink { feedAction("bubble.right.fill", count: item.fitCheckComments.count, label: "Comments") }
            ShareLink(item: "Check out this Fit-Check on CLO·V") {
                feedAction("paperplane.fill", count: nil, label: "Share")
            }
            .simultaneousGesture(TapGesture().onEnded { onEvent("share") })
        }
        .frame(width: 50)
    }

    private var avatarButton: some View {
        Button {
            guard canFollow else { return }
            onToggleFollow(!isFollowing)
        } label: {
            AvatarView(url: item.profiles?.avatarUrl, nickname: item.profiles?.nickname, size: 46, ringed: true)
                .overlay(alignment: .bottom) {
                    if canFollow {
                        Image(systemName: isFollowing ? "checkmark" : "plus")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Theme.accent, in: Circle())
                            .offset(y: 8)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!canFollow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Follow \(nickname)")
        .accessibilityValue(isFollowing ? "Following" : "Not following")
        .accessibilityAddTraits([.isButton, .isToggle])
        .accessibilityHidden(!canFollow)
    }

    private func detailLink<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        NavigationLink {
            FitCheckDetailView(fitCheckId: item.id)
        } label: {
            label()
        }
        .simultaneousGesture(TapGesture().onEnded { onEvent("open_detail") })
    }

    private func feedAction(_ symbol: String, count: Int?, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            if let count {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
            }
        }
        .frame(minWidth: 48, minHeight: 46)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { "\(label), \($0)" } ?? label)
    }
}
