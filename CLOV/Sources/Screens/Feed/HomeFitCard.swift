import SwiftUI

/// Feed post in the editorial hero style: a full-bleed photo with nearly square corners
/// (auto-rotating; press and hold to vote for the look on screen), a row hanging off its
/// bottom edge (Like and Comment in small white pills, a large black Vote pill), then the
/// author, look thumbnails, the results once revealed, and the caption. Voting goes
/// through `ReelVoteModel`, so the optimistic update, rollback and resync match the rest
/// of the app.
struct HomeFitCard: View {
    let item: FeedItemDTO
    let viewerId: UUID
    let isLiked: Bool
    let isFollowing: Bool
    let showsFollow: Bool
    let onToggleFollow: (Bool) -> Void
    let onLike: (Bool) async throws -> Void
    let onComment: () -> Void
    /// Opens the full-screen vote screen on a look; `nil` while that screen is hidden.
    let onOpen: ((Int) -> Void)?
    /// The viewer's vote (`nil` after an undo) and the new total, once the server confirmed it.
    let onVoteChange: (UUID?, Int) -> Void
    var onPhotoDisplay: (() -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @StateObject private var model: ReelVoteModel
    @State private var photoIndex = 0
    @State private var isHoldingToVote = false
    @ScaledMetric(relativeTo: .body) private var heroRowHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var smallPillHeight: CGFloat = 40
    private static let votePillMinWidth: CGFloat = 150
    /// Dots sit 10pt above the carousel's foot and are about 19pt tall.
    private static let hiddenDotsInset: CGFloat = 32

    init(item: FeedItemDTO, viewerId: UUID, isLiked: Bool, isFollowing: Bool, showsFollow: Bool,
         onToggleFollow: @escaping (Bool) -> Void, onLike: @escaping (Bool) async throws -> Void,
         onComment: @escaping () -> Void, onOpen: ((Int) -> Void)?,
         onVoteChange: @escaping (UUID?, Int) -> Void,
         onPhotoDisplay: (() -> Void)? = nil) {
        self.item = item
        self.viewerId = viewerId
        self.isLiked = isLiked
        self.isFollowing = isFollowing
        self.showsFollow = showsFollow
        self.onToggleFollow = onToggleFollow
        self.onLike = onLike
        self.onComment = onComment
        self.onOpen = onOpen
        self.onVoteChange = onVoteChange
        self.onPhotoDisplay = onPhotoDisplay
        _model = StateObject(wrappedValue: ReelVoteModel(item: item, voterId: viewerId))
    }

    private var photoURLs: [URL] { PostCardContent.photoURLs(item.fitCheckPhotos) }
    private var posterName: String { item.profiles?.nickname ?? "Someone" }
    private var title: String { PostCardContent.title(votePrompt: item.votePrompt, occasion: item.occasion) }
    private var shownPhoto: FitCheckPhoto? { PostCardContent.photo(at: photoIndex, in: model.photos) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            TimelineView(.expiry(item.expiresAt)) { _ in
                hero(expired: isExpired(item.expiresAt))
            }
            .accessibilitySortPriority(1)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // The photo is for press-and-hold voting, so the long-press menu lives on the
                // author row; it reads first so VoiceOver meets the author before the photo.
                HomeFitCardActions(item: item, title: title, posterName: posterName, viewerId: viewerId,
                                   isFollowing: isFollowing,
                                   onToggleFollow: showsFollow ? onToggleFollow : nil)
                    .fitCheckContextMenu(fitCheckId: item.id, creatorId: item.creatorId, posterName: posterName,
                                         viewerId: viewerId, isFollowing: isFollowing,
                                         onToggleFollow: showsFollow ? onToggleFollow : nil)
                    .accessibilitySortPriority(2)
                if photoURLs.count > 1 {
                    ThumbnailStrip(urls: photoURLs, selectedIndex: $photoIndex)
                }
                voteStatus
                if let caption = item.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
                    Text(caption)
                        .font(Theme.font(.subheadline))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                }
                StyleTagRow(tags: PostCardContent.displayTags(item.tags, limit: 3))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(posterName)’s Fit-Check")
        .accessibilityIdentifier("feed-post-card")
        .task { await model.loadSummary() }
        .onChange(of: item.ownVote(voterId: viewerId)) { _, seeded in
            guard let seeded, seeded != model.myVote else { return }
            Task { await model.refreshSummary() }
        }
    }

    // MARK: Hero photo

    private func hero(expired: Bool) -> some View {
        let canVote = model.canVote && !expired
        let content = FitCardContent(item: item, photoIndex: photoIndex, revealsVotes: model.isResultsRevealed)
        return FitCard(content: content, captionBottomInset: heroRowHeight / 2 + Spacing.l) {
            PhotoCarousel(urls: photoURLs, currentIndex: $photoIndex,
                          autoAdvance: !expired && !isHoldingToVote && model.myVote == nil,
                          contentMode: .fill, accessibilityIdentifier: "feed-photo-carousel",
                          onTap: onOpen.map { open in { open(photoIndex) } },
                          prioritizesSelectedPhoto: true, onPhotoDisplay: onPhotoDisplay)
                // The carousel draws page dots at its foot; run it past the clipped edge so the
                // dots stay hidden behind the hanging row. The thumbnails show the position.
                .padding(.bottom, -Self.hiddenDotsInset)
        }
        .overlay { if expired { endedOverlay } }
        .holdToVote(isEnabled: canVote, isPressing: $isHoldingToVote) { castVoteForShownPhoto() }
        // The action row hangs half off the photo's bottom edge.
        .overlay(alignment: .bottom) {
            heroRow(canVote: canVote)
                .padding(.horizontal, Spacing.sm)
                .offset(y: heroRowHeight / 2)
        }
        .padding(.bottom, heroRowHeight / 2)
    }

    private func heroRow(canVote: Bool) -> some View {
        HStack(spacing: Spacing.s) {
            Spacer(minLength: 0)
            LikeButton(isLiked: isLiked, count: PostCardContent.displayLikeCount(item.likeCount),
                       accessibilityIdentifier: "feed-like-button", perform: onLike)
                .modifier(WhitePill(height: smallPillHeight))
            Button(action: onComment) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "bubble.left")
                    if let count = PostCardContent.displayLikeCount(item.fitCheckComments.count) {
                        Text("\(count)").font(Theme.font(.footnote, weight: .semibold)).monospacedDigit()
                    }
                }
                .foregroundStyle(Color.black)
                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(InstantPressStyle())
            .modifier(WhitePill(height: smallPillHeight))
            .accessibilityLabel("Comments")
            .accessibilityValue(item.fitCheckComments.isEmpty ? "" : "\(item.fitCheckComments.count)")
            .accessibilityIdentifier("feed-comment-button")
            votePill(canVote: canVote)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func votePill(canVote: Bool) -> some View {
        Button(action: castVoteForShownPhoto) {
            Text(votePillTitle)
                .font(Theme.font(.headline, weight: .bold))
                .tracking(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Theme.primaryButtonText)
                .padding(.horizontal, Spacing.l)
                .frame(minWidth: Self.votePillMinWidth, minHeight: heroRowHeight)
                .background(Theme.primaryButtonFill, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(InstantPressStyle())
        .disabled(!canVote)
        .accessibilityLabel(canVote ? "Vote for \(shownLookTitle)" : votePillTitle)
        .accessibilityIdentifier("feed-vote-hero")
    }

    private var shownLookTitle: String {
        shownPhoto.map { PostCardContent.voteButtonTitle(position: $0.position) } ?? "this look"
    }

    private var votePillTitle: String {
        if model.myVote != nil { return "VOTED" }
        if model.isEnded { return "ENDED" }
        if model.isCreator { return "YOUR POST" }
        return "VOTE \(shownLookTitle.uppercased())"
    }

    private var endedOverlay: some View {
        RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
            .fill(.black.opacity(0.45))
            .overlay {
                Label("Voting ended", systemImage: "checkmark.seal")
                    .font(Theme.headline)
                    .foregroundStyle(.white)
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Voting ended")
    }

    // MARK: Voting

    private var voteOptions: [VoteOption] {
        let top = model.counts.values.max() ?? 0
        return model.photos.map { photo in
            VoteOption(id: photo.id, title: PostCardContent.voteButtonTitle(position: photo.position),
                       percent: model.percent(for: photo.id),
                       isLeading: top > 0 && (model.counts[photo.id] ?? 0) == top)
        }
    }

    /// Before voting: a hint (the thumbnails pick the look, Vote casts it). After voting,
    /// or when results are open to the viewer: the insight and each look's share.
    @ViewBuilder
    private var voteStatus: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if model.isResultsRevealed {
                if let insight = model.insight {
                    Label(insight, systemImage: "sparkles")
                        .font(Theme.font(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("feed-vote-insight")
                }
                VoteButtons(options: voteOptions, highlightedID: shownPhoto?.id, myVote: model.myVote,
                            isRevealed: true, canVote: false, footer: footerText, identifierPrefix: "feed-vote",
                            onVote: { _ in }, onUndo: model.canRetract ? undo : nil)
            } else if model.canVote {
                Text("Pick a look, then tap Vote. Or hold the photo.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityIdentifier("feed-vote-hint")
            }
            if let error = model.error {
                Text(error)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("feed-vote-error")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var footerText: String {
        let votes = model.total == 1 ? "1 vote" : "\(model.total) votes"
        if model.isEnded { return "Voting ended · \(votes)" }
        if model.isCreator { return "Your Fit-Check · \(votes)" }
        return votes
    }

    private func castVoteForShownPhoto() {
        guard model.canVote, let photo = shownPhoto else { return }
        Haptics.impact(.medium)
        let started = model.vote(for: photo.id) { recorded() }
        AccessibilityNotification.Announcement(started ? "Vote recorded, results shown" : "Vote not recorded").post()
    }

    private func undo() {
        guard model.canRetract else { return }
        Haptics.impact(.light)
        model.retractVote { recorded() }
        AccessibilityNotification.Announcement("Vote undone. Pick again.").post()
    }

    /// The server confirmed a vote or an undo: tell the feed, and refresh other screens
    /// without reloading the feed underneath the viewer.
    private func recorded() {
        onVoteChange(model.myVote, model.total)
        appState.contentDidChange(reloadHomeFeed: false)
    }
}

/// Small white pill for the icons hanging off the hero photo. Always light, so the
/// icons stay dark on white in dark mode too.
private struct WhitePill: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.sm)
            .frame(minWidth: height * 1.4, minHeight: height)
            .background(Color.white, in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            .environment(\.colorScheme, .light)
    }
}
