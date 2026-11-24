import SwiftUI

/// Feed post in the editorial hero style: a full-bleed photo with nearly square corners
/// (auto-rotating; hold for two seconds to vote for the look on screen, double-tap to open
/// the voting screen), a row hanging off its
/// bottom edge (Like and Comment in small outlined boxes, a black HUD-style Vote block with a
/// gauge, and Undo beside it once voted), then the
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
    /// Opens the full-screen vote screen on a look (a double tap on the photo); `nil` while that screen is hidden.
    let onOpen: ((Int) -> Void)?
    /// The viewer's vote (`nil` after an undo) and the new total, once the server confirmed it.
    let onVoteChange: (UUID?, Int) -> Void
    var onPhotoDisplay: (() -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: ReelVoteModel
    @State private var photoIndex = 0
    @State private var isHoldingToVote = false
    /// 0...1 while a finger holds the photo; drives the Vote block's gauge.
    @State private var holdProgress: Double = 0
    @ScaledMetric(relativeTo: .body) private var heroRowHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var smallPillHeight: CGFloat = 40
    /// Dots sit 10pt above the carousel's foot and are about 19pt tall.
    private static let hiddenDotsInset: CGFloat = 32
    /// Seconds a finger must stay on the photo to vote, long enough that a scroll or a tap never votes.
    static let holdToVoteSeconds: TimeInterval = 2

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
                          onDoubleTap: onOpen.map { open in { open(photoIndex) } },
                          prioritizesSelectedPhoto: true, onPhotoDisplay: onPhotoDisplay)
                // The carousel draws page dots at its foot; run it past the clipped edge so the
                // dots stay hidden behind the hanging row. The thumbnails show the position.
                .padding(.bottom, -Self.hiddenDotsInset)
                // On the carousel itself, beside its own gestures, so a hold always reaches it.
                .holdToVote(isEnabled: canVote, isPressing: $isHoldingToVote, progress: $holdProgress,
                            duration: Self.holdToVoteSeconds) {
                    castVoteForShownPhoto()
                }
        }
        .overlay { if expired { endedOverlay } }
        // Once revealed, a small tag in the top-left corner (opposite the countdown) gives the
        // shown look's share, so the outfit itself stays uncovered.
        .overlay(alignment: .topLeading) {
            if model.isResultsRevealed {
                resultBadge
                    .transition(resultTransition)
                    .padding(Spacing.sm)
            }
        }
        .animation(Theme.animation(Self.resultSpring, reduceMotion: reduceMotion), value: model.isResultsRevealed)
        // The action row hangs half off the photo's bottom edge.
        .overlay(alignment: .bottom) {
            heroRow(canVote: canVote)
                .padding(.horizontal, Spacing.sm)
                .offset(y: heroRowHeight / 2)
        }
        .padding(.bottom, heroRowHeight / 2)
    }

    private func heroRow(canVote: Bool) -> some View {
        HStack(spacing: Spacing.xs) {
            Spacer(minLength: 0)
            LikeButton(isLiked: isLiked, count: PostCardContent.displayLikeCount(item.likeCount),
                       accessibilityIdentifier: "feed-like-button", perform: onLike)
                .modifier(HudIconBox(height: smallPillHeight))
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
            .modifier(HudIconBox(height: smallPillHeight))
            .accessibilityLabel("Comments")
            .accessibilityValue(item.fitCheckComments.isEmpty ? "" : "\(item.fitCheckComments.count)")
            .accessibilityIdentifier("feed-comment-button")
            voteBlock(canVote: canVote)
            if model.canRetract {
                HudUndoButton(height: heroRowHeight, action: undo)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Before a vote: a button that votes for the look on screen, its gauge following a hold.
    /// After: a read-out of the picked look and its share of the votes; Undo sits beside it.
    @ViewBuilder
    private func voteBlock(canVote: Bool) -> some View {
        if let gaugePhoto = resultPhoto {
            HudVoteBlock(title: voteBlockTitle, detail: HudStyle.lookCode(position: gaugePhoto.position),
                         fraction: Double(model.percent(for: gaugePhoto.id)) / 100,
                         isVoted: model.myVote != nil, minHeight: heroRowHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(resultAccessibilityLabel(for: gaugePhoto))
                .accessibilityIdentifier("feed-vote-hero")
        } else {
            Button(action: castVoteForShownPhoto) {
                HudVoteBlock(title: voteBlockTitle,
                             detail: shownPhoto.map { "→ " + HudStyle.lookCode(position: $0.position) },
                             fraction: holdProgress, isVoted: false, minHeight: heroRowHeight,
                             isTracking: isHoldingToVote)
                    .contentShape(Rectangle())
            }
            .buttonStyle(InstantPressStyle())
            .disabled(!canVote)
            .accessibilityLabel(canVote ? "Vote for \(shownLookTitle)" : voteBlockTitle)
            .accessibilityIdentifier("feed-vote-hero")
        }
    }

    /// The look the gauge reports once results are revealed: the viewer's pick, else
    /// (creator, ended) the look on screen. `nil` before results, while the gauge tracks a hold.
    private var resultPhoto: FitCheckPhoto? {
        guard model.isResultsRevealed else { return nil }
        if let myVote = model.myVote, let picked = model.photos.first(where: { $0.id == myVote }) {
            return picked
        }
        return shownPhoto
    }

    private var shownLookTitle: String {
        shownPhoto.map { PostCardContent.voteButtonTitle(position: $0.position) } ?? "this look"
    }

    private func resultAccessibilityLabel(for photo: FitCheckPhoto) -> String {
        let look = PostCardContent.voteButtonTitle(position: photo.position)
        let share = "\(model.percent(for: photo.id)) percent"
        return model.myVote != nil ? "Voted for \(look), \(share)" : "\(voteBlockTitle), \(look), \(share)"
    }

    private var voteBlockTitle: String {
        if model.myVote != nil { return "✓ VOTED" }
        if model.isEnded { return "ENDED" }
        if model.isCreator { return "YOUR POST" }
        return "VOTE"
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

    // MARK: Result on the photo

    private static let resultSpring = Animation.spring(response: 0.42, dampingFraction: 0.68)
    /// Darker than a plain yellow so the crown reads on the white tag.
    private static let crownGold = Color(red: 0.84, green: 0.6, blue: 0.05)
    private static let badgeCornerRadius: CGFloat = 2

    private var resultTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity)
    }

    /// The shown look's share as a white tag matching the countdown: a check on the
    /// viewer's pick and a crown on the leader. It follows the thumbnails and swipes.
    @ViewBuilder
    private var resultBadge: some View {
        if let photo = shownPhoto {
            let percent = model.percent(for: photo.id)
            let isMine = model.myVote == photo.id
            let isLeading = isLeadingPhoto(photo.id)
            let title = PostCardContent.voteButtonTitle(position: photo.position)
            HStack(spacing: Spacing.xs) {
                if isMine {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text("\(percent)%")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
                if isLeading {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Self.crownGold)
                }
            }
            .font(Theme.font(.subheadline, weight: .bold))
            // The tag is always white, so its text stays dark in dark mode too.
            .foregroundStyle(Color.black)
            .padding(.horizontal, Spacing.s + 2)
            .padding(.vertical, Spacing.xs + 1)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Self.badgeCornerRadius, style: .continuous))
            .motionSafeAnimation(Theme.snap, value: photo.id)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(percent) percent\(isMine ? ", your vote" : "")\(isLeading ? ", leading" : "")")
            .accessibilityIdentifier("feed-vote-results")
        }
    }

    /// True for the look (or looks, on a tie) with the most votes, once anyone has voted.
    private func isLeadingPhoto(_ id: UUID) -> Bool {
        let top = model.counts.values.max() ?? 0
        return top > 0 && (model.counts[id] ?? 0) == top
    }

    // MARK: Voting

    /// Before voting: a hint (the thumbnails pick the look, Vote casts it). After voting the
    /// share sits on the photo, and the total, the insight line and Undo sit here.
    @ViewBuilder
    private var voteStatus: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if model.isResultsRevealed {
                HStack {
                    Text(footerText)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("feed-vote-insight")
                    Spacer(minLength: 0)
                }
            } else if model.canVote {
                Text("Pick a look, then tap Vote. Or hold the photo for 2 seconds.")
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
        guard let insight = model.insight else { return votes }
        return "\(votes) · \(insight)"
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
