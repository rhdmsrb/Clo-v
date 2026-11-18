import SwiftUI

/// Home post card in the editorial style: a white rounded card holding the full-bleed
/// `FitCard` photo (auto-rotating; press and hold to vote for the look on screen), a
/// thumbnail strip of the looks, pill `VoteButtons` that turn into result bars, and
/// the Like / Comment / Send row. Voting goes through `ReelVoteModel`, so the
/// optimistic update, rollback and resync match the rest of the app.
struct HomeFitCard: View {
    let item: FeedItemDTO
    let viewerId: UUID
    let isLiked: Bool
    let isFollowing: Bool
    let showsFollow: Bool
    let onToggleFollow: (Bool) -> Void
    let onLike: (Bool) async throws -> Void
    let onComment: () -> Void
    /// The viewer's vote (`nil` after an undo) and the new total, once the server confirmed it.
    let onVoteChange: (UUID?, Int) -> Void
    var onPhotoDisplay: (() -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @StateObject private var model: ReelVoteModel
    @State private var photoIndex = 0
    @State private var isHoldingToVote = false

    private static let cardPadding: CGFloat = Spacing.s
    private static let photoRadius: CGFloat = Radius.card - Spacing.s
    /// The carousel's page dots sit 10pt above the photo's foot and are ~19pt tall.
    private static let captionAboveDots: CGFloat = Spacing.xl + Spacing.xs

    init(item: FeedItemDTO, viewerId: UUID, isLiked: Bool, isFollowing: Bool, showsFollow: Bool,
         onToggleFollow: @escaping (Bool) -> Void, onLike: @escaping (Bool) async throws -> Void,
         onComment: @escaping () -> Void, onVoteChange: @escaping (UUID?, Int) -> Void,
         onPhotoDisplay: (() -> Void)? = nil) {
        self.item = item
        self.viewerId = viewerId
        self.isLiked = isLiked
        self.isFollowing = isFollowing
        self.showsFollow = showsFollow
        self.onToggleFollow = onToggleFollow
        self.onLike = onLike
        self.onComment = onComment
        self.onVoteChange = onVoteChange
        self.onPhotoDisplay = onPhotoDisplay
        _model = StateObject(wrappedValue: ReelVoteModel(item: item, voterId: viewerId))
    }

    private var photoURLs: [URL] { PostCardContent.photoURLs(item.fitCheckPhotos) }
    private var posterName: String { item.profiles?.nickname ?? "Someone" }
    private var title: String { PostCardContent.title(votePrompt: item.votePrompt, occasion: item.occasion) }
    private var shownPhoto: FitCheckPhoto? { PostCardContent.photo(at: photoIndex, in: model.photos) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TimelineView(.expiry(item.expiresAt)) { _ in
                photoCard(expired: isExpired(item.expiresAt))
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if photoURLs.count > 1 {
                    ThumbnailStrip(urls: photoURLs, selectedIndex: $photoIndex)
                }
                voteSection
                HomeFitCardActions(item: item, title: title, posterName: posterName, viewerId: viewerId,
                                   isLiked: isLiked, isFollowing: isFollowing,
                                   onToggleFollow: showsFollow ? onToggleFollow : nil,
                                   onLike: onLike, onComment: onComment)
                if let caption = item.caption?.trimmingCharacters(in: .whitespacesAndNewlines), !caption.isEmpty {
                    Text(caption)
                        .font(Theme.font(.subheadline))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, Spacing.xs)
        }
        .padding(Self.cardPadding)
        .padding(.bottom, Spacing.xs)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(posterName)’s Fit-Check")
        .accessibilityIdentifier("feed-post-card")
        .task { await model.loadSummary() }
        .onChange(of: item.ownVote(voterId: viewerId)) { _, seeded in
            guard let seeded, seeded != model.myVote else { return }
            Task { await model.refreshSummary() }
        }
    }

    // MARK: Photo

    private func photoCard(expired: Bool) -> some View {
        let canVote = model.canVote && !expired
        let content = FitCardContent(item: item, photoIndex: photoIndex,
                                     revealsVotes: model.isResultsRevealed)
        return FitCard(content: content, aspectRatio: 4.0 / 5.0, cornerRadius: Self.photoRadius,
                       captionBottomInset: photoURLs.count > 1 ? Self.captionAboveDots : Spacing.m) {
            PhotoCarousel(urls: photoURLs, currentIndex: $photoIndex,
                          autoAdvance: !expired && !isHoldingToVote && model.myVote == nil,
                          keepsRotatingAfterTouch: true,
                          contentMode: .fill, accessibilityIdentifier: "feed-photo-carousel",
                          prioritizesSelectedPhoto: true, onPhotoDisplay: onPhotoDisplay)
        }
        .overlay { if expired { endedOverlay } }
        .holdToVote(isEnabled: canVote, isPressing: $isHoldingToVote) { castVoteForShownPhoto() }
    }

    private var endedOverlay: some View {
        RoundedRectangle(cornerRadius: Self.photoRadius, style: .continuous)
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

    @ViewBuilder
    private var voteSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if model.isResultsRevealed, let insight = model.insight {
                Label(insight, systemImage: "sparkles")
                    .font(Theme.font(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.accentDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("feed-vote-insight")
            } else if model.canVote {
                Text("Tap a look, or hold the photo, to vote")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityIdentifier("feed-vote-hint")
            }
            VoteButtons(options: voteOptions, highlightedID: shownPhoto?.id, myVote: model.myVote,
                        isRevealed: model.isResultsRevealed, canVote: model.canVote,
                        footer: footerText, identifierPrefix: "feed-vote",
                        onVote: vote(for:), onUndo: model.canRetract ? undo : nil)
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
        guard let photo = shownPhoto else { return }
        vote(for: photo.id)
    }

    private func vote(for photoId: UUID) {
        if let index = model.photos.firstIndex(where: { $0.id == photoId }) { photoIndex = index }
        let started = model.vote(for: photoId) { recorded() }
        AccessibilityNotification.Announcement(started ? "Vote recorded, results shown" : "Vote not recorded").post()
    }

    private func undo() {
        guard model.canRetract else { return }
        Haptics.impact(.light)
        model.retractVote { recorded() }
        AccessibilityNotification.Announcement("Vote undone. Pick again.").post()
    }

    /// The server confirmed a vote or an undo: tell Home, and refresh other screens
    /// without reloading Home underneath the viewer.
    private func recorded() {
        onVoteChange(model.myVote, model.total)
        appState.contentDidChange(reloadHomeFeed: false)
    }
}
