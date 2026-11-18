import SwiftUI

/// Feed post: author, prompt title, auto-rotating photos, a vote row (one button
/// per look, then the results), Like / Comment / Send row, occasion and
/// description. Votes are cast on the card.
struct FeedPostCard: View {
    let item: FeedItemDTO
    let isLiked: Bool
    /// The signed-in viewer; the long-press menu hides report/block on their own posts.
    let viewerId: UUID
    let isFollowing: Bool
    let showsFollow: Bool
    let onToggleFollow: (Bool) -> Void
    let onLike: (Bool) async throws -> Void
    /// Opens the vote screen on the photo currently showing in the carousel.
    let onOpen: ((Int) -> Void)?
    /// Opens the comment thread sheet.
    let onComment: () -> Void
    /// The viewer's vote on this post once the server confirmed it (`nil` after an undo).
    var onVoteChange: (UUID?) -> Void = { _ in }
    var onPhotoDisplay: (() -> Void)?

    @State private var comparing = false
    @State private var photoIndex = 0
    /// True while a press-and-hold vote is in progress; the photos stop rotating so the press stays on one look.
    @State private var isHoldingToVote = false
    /// A hold that ends on the photo must not also count as a tap that opens the vote screen.
    @State private var holdStartedAt: Date?
    @State private var ignoreOpenUntil = Date.distantPast
    /// Bumped by a tap on the photo while the vote screen is hidden, so the on-photo hint bounces.
    @State private var holdHintNudge = 0
    /// True for a moment after voting, so the carousel stays on the look the viewer picked.
    @State private var isShowingOwnVote = false
    @State private var voteDwellToken = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Tall 9:16 (width : height), like a phone photo or story, so the outfit gets most
    /// of the screen. Each photo fills the frame, so other shapes lose a little at the edges
    /// instead of showing bars.
    private static let photoAspectRatio: CGFloat = 9.0 / 16.0
    private static let descriptionLineLimit = 2
    /// Side inset for text; the photo itself spans the full width.
    private static let textInset: CGFloat = 16
    /// A press longer than this is a hold, so its release must not open the vote screen.
    private static let holdMinimumDuration: TimeInterval = 0.25
    private static let openSuppressionAfterHold: TimeInterval = 0.4
    /// Longer than one carousel interval, so the picked look's result is the first one seen.
    private static let voteDwellDuration: Duration = .seconds(5)
    private static let photoBadgeInset: CGFloat = 12
    private static let hintNudgeScale: CGFloat = 1.12

    private var posterName: String { item.profiles?.nickname ?? "Someone" }
    private var title: String { PostCardContent.title(votePrompt: item.votePrompt, occasion: item.occasion) }
    private var photoURLs: [URL] { PostCardContent.photoURLs(item.fitCheckPhotos) }
    private var commentCount: Int { item.commentCount }

    var body: some View {
        // Photo first: author, full-bleed photo, actions, then one title line.
        // No card surface or shadow, so the clothes carry the screen.
        VStack(alignment: .leading, spacing: 10) {
            withContextMenu(header.padding(.horizontal, Self.textInset))
            FeedCardVoteSection(item: item, viewerId: viewerId, photoIndex: photoIndex,
                                textInset: Self.textInset, onVoteChange: onVoteChange) { vote in
                VStack(alignment: .leading, spacing: 10) {
                    // One timeline per card, ticking once at expiry.
                    TimelineView(.expiry(item.expiresAt)) { _ in
                        if comparing {
                            InlineLookComparison(item: item, viewerId: viewerId,
                                                 onOpen: FitCheckReelView.isEnabled ? onOpen : nil)
                        } else {
                            photos(expired: isExpired(item.expiresAt), vote: vote)
                        }
                    }
                    if item.fitCheckPhotos.count >= 2 {
                        Button(comparing ? "Show carousel" : "Compare looks") { comparing.toggle() }
                            .font(Theme.bodyEmphasis)
                            .frame(minHeight: Theme.minTapSize)
                            .padding(.horizontal, Self.textInset)
                            .accessibilityIdentifier("feed.compare")
                    }
                }
            }
            actionRow.padding(.horizontal, Self.textInset - 6)
            withContextMenu(
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    details
                }
                .padding(.horizontal, Self.textInset)
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(posterName)’s Fit-Check")
        .accessibilityIdentifier("feed-post-card")
        .task(id: voteDwellToken) { await endVoteDwell() }
    }

    /// The long-press menu (Share, Report, Block) is kept off the photos and the vote area: a long
    /// press there is the vote, and a menu would take the press over. The "…" button offers the same entries.
    private func withContextMenu<Content: View>(_ content: Content) -> some View {
        content.fitCheckContextMenu(
            fitCheckId: item.id, creatorId: item.creatorId, posterName: posterName, viewerId: viewerId,
            isFollowing: isFollowing, onToggleFollow: showsFollow ? onToggleFollow : nil
        )
    }

    /// At accessibility text sizes the name and the Follow button stack, so
    /// neither truncates ("maya.c…", "Follo…").
    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                authorRow(nameLineLimit: 2)
                HStack(spacing: 8) {
                    if showsFollow { followButton }
                    Spacer(minLength: 0)
                    moreMenu
                }
            }
        } else {
            HStack(spacing: 10) {
                authorRow(nameLineLimit: 1)
                Spacer(minLength: 0)
                if showsFollow { followButton }
                moreMenu
            }
        }
    }

    /// Visible home for Share, Report and Block; the long-press menu offers
    /// the same entries but nothing on screen hints that it exists.
    private var moreMenu: some View {
        FitCheckMoreMenu(
            fitCheckId: item.id, creatorId: item.creatorId, posterName: posterName, viewerId: viewerId,
            isFollowing: isFollowing, onToggleFollow: showsFollow ? onToggleFollow : nil
        )
        // Pull the 44pt target's padding into the card's text inset.
        .padding(.trailing, -10)
    }

    private func authorRow(nameLineLimit: Int) -> some View {
        HStack(spacing: 10) {
            AvatarView(url: item.profiles?.avatarUrl, nickname: item.profiles?.nickname, size: 40)
            Text(posterName)
                .font(Theme.headline.weight(.bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(nameLineLimit)
        }
    }

    private var followButton: some View {
        Button { onToggleFollow(!isFollowing) } label: {
            Label(isFollowing ? "Following" : "Follow", systemImage: isFollowing ? "checkmark" : "plus")
                .font(Theme.caption)
                .foregroundStyle(isFollowing ? Theme.accentDeep : Theme.ink)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(isFollowing ? Theme.accentTint : Color.clear, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous)
                    .stroke(isFollowing ? Theme.accentDeep : Theme.controlBorder, lineWidth: 1))
                .frame(minHeight: Theme.minTapSize)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isFollowing)
        .accessibilityLabel("Follow \(posterName)")
        .accessibilityValue(isFollowing ? "Following" : "Not following")
        .accessibilityAddTraits(.isToggle)
    }

    private func photos(expired: Bool, vote: PhotoVoteAction) -> some View {
        let canVote = vote.isEnabled && !expired
        return PhotoCarousel(urls: photoURLs, currentIndex: $photoIndex,
                             autoAdvance: !expired && !isHoldingToVote && !isShowingOwnVote,
                             keepsRotatingAfterTouch: true,
                             contentMode: .fill, accessibilityIdentifier: "feed-photo-carousel",
                             onTap: { handlePhotoTap(canVote: canVote) },
                             prioritizesSelectedPhoto: true, onPhotoDisplay: onPhotoDisplay)
            .aspectRatio(Self.photoAspectRatio, contentMode: .fit)
            .overlay { if expired { endedOverlay } }
            // The vote hint and the text below the photo sit under the fold on a tall photo,
            // so the photo itself says how to vote and how many looks there are.
            .overlay(alignment: .top) { photoBadges(canVote: canVote) }
            .clipped()
            .contentShape(Rectangle())
            .holdToVote(isEnabled: canVote, isPressing: $isHoldingToVote) { castAndShowOwnVote(vote) }
            .onChange(of: isHoldingToVote) { _, holding in noteHold(holding) }
            .accessibilityAddTraits(onOpen == nil ? [] : .isButton)
            .accessibilityActions {
                if let onOpen {
                    Button(expired ? "See results" : "Open to vote") { onOpen(photoIndex) }
                }
            }
    }

    /// A tap opens the vote screen when it is shown. While it is hidden a tap would do nothing, so
    /// it points at the hold instead. The release of a hold is not a tap.
    private func handlePhotoTap(canVote: Bool) {
        guard Date() >= ignoreOpenUntil else { return }
        if let onOpen {
            onOpen(photoIndex)
            return
        }
        guard canVote else { return }
        holdHintNudge += 1
        Haptics.impact(.light)
        AccessibilityNotification.Announcement("Press and hold the photo to vote").post()
    }

    /// Votes, then holds the carousel on the picked look so its result shows first.
    private func castAndShowOwnVote(_ vote: PhotoVoteAction) {
        vote.cast()
        isShowingOwnVote = true
        voteDwellToken += 1
    }

    /// Lets the carousel rotate again a few seconds after a vote. Re-keyed by each vote.
    private func endVoteDwell() async {
        guard isShowingOwnVote else { return }
        try? await Task.sleep(for: Self.voteDwellDuration)
        guard !Task.isCancelled else { return }
        isShowingOwnVote = false
    }

    private func photoBadges(canVote: Bool) -> some View {
        HStack(alignment: .top) {
            if canVote { holdHint }
            Spacer(minLength: 0)
            if photoURLs.count > 1 { pageCounter }
        }
        .padding(Self.photoBadgeInset)
        .allowsHitTesting(false)
    }

    private var holdHint: some View {
        Label("Hold to vote", systemImage: "hand.tap.fill")
            .font(Theme.font(.footnote, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.black.opacity(0.55), in: Capsule())
            .phaseAnimator([false, true, false], trigger: holdHintNudge) { content, isUp in
                content.scaleEffect(isUp && !reduceMotion ? Self.hintNudgeScale : 1)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Press and hold the photo to vote")
            .accessibilityIdentifier("feed-photo-hold-hint")
    }

    /// "2/4": which look is showing. The dots at the photo's foot are under the fold on a tall photo.
    private var pageCounter: some View {
        Text("\(photoIndex + 1)/\(photoURLs.count)")
            .font(Theme.font(.footnote, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.black.opacity(0.55), in: Capsule())
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            // The carousel already reads "Photo 2 of 4".
            .accessibilityHidden(true)
    }

    private func noteHold(_ holding: Bool) {
        if holding {
            holdStartedAt = Date()
            return
        }
        defer { holdStartedAt = nil }
        guard let startedAt = holdStartedAt, Date().timeIntervalSince(startedAt) > Self.holdMinimumDuration else { return }
        ignoreOpenUntil = Date().addingTimeInterval(Self.openSuppressionAfterHold)
    }

    private var endedOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
            Label("Voting ended", systemImage: "checkmark.seal")
                .font(Theme.headline)
                .foregroundStyle(.white)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voting ended")
    }

    private var actionRow: some View {
        HStack(spacing: 4) {
            LikeButton(isLiked: isLiked, count: PostCardContent.displayLikeCount(item.likeCount), title: "Like", accessibilityIdentifier: "feed-like-button", perform: onLike)
            Button(action: onComment) {
                rowLabel("Comment", systemImage: "bubble.left", count: PostCardContent.displayLikeCount(commentCount))
            }
            .buttonStyle(InstantPressStyle())
            .accessibilityLabel("Comments")
            .accessibilityValue(commentCount > 0 ? "\(commentCount)" : "")
            .accessibilityIdentifier("feed-comment-button")
            ShareLink(item: PostCardContent.shareText(title: title, url: ShareURL.make(fitCheckId: item.id)),
                      subject: Text(title)) {
                rowLabel("Send", systemImage: "paperplane")
            }
            .buttonStyle(InstantPressStyle())
            .accessibilityLabel("Send")
            .accessibilityIdentifier("feed-send-button")
            Spacer(minLength: 0)
        }
        .font(.system(.title3))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func rowLabel(_ text: String, systemImage: String, count: Int? = nil) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text).font(Theme.font(.footnote, weight: .semibold)).lineLimit(1)
            if let count {
                Text("\(count)").font(Theme.font(.footnote, weight: .semibold)).monospacedDigit()
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 6)
        .frame(minHeight: Theme.minTapSize)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var tagsRow: some View {
        let tags = PostCardContent.displayTags(item.tags)
        if !tags.isEmpty {
            Text(tags.joined(separator: " "))
                .font(Theme.micro)
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
                .accessibilityLabel("Tags: \(tags.joined(separator: ", "))")
        }
    }

    @ViewBuilder
    private var details: some View {
        if let caption = item.caption, !caption.isEmpty {
            Text(caption)
                .font(Theme.font(.subheadline))
                .foregroundStyle(Theme.ink)
                .lineLimit(Self.descriptionLineLimit)
        }
        // Occasion is plain muted text, not a pill, so rose stays reserved for actions.
        if let occasion = item.occasion, !occasion.isEmpty {
            Text(occasion)
                .font(Theme.micro)
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
        }
        tagsRow
    }
}

private struct InlineLookComparison: View {
    @StateObject private var model: ReelVoteModel
    /// Opens the vote screen on a look; `nil` while that screen is hidden.
    let onOpen: ((Int) -> Void)?

    init(item: FeedItemDTO, viewerId: UUID, onOpen: ((Int) -> Void)?) {
        _model = StateObject(wrappedValue: ReelVoteModel(item: item, voterId: viewerId))
        self.onOpen = onOpen
    }

    var body: some View {
        VStack {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                    VStack {
                        if let onOpen {
                            Button { onOpen(index) } label: { lookImage(photo) }
                                .accessibilityLabel("Enlarge look \(index + 1)")
                        } else {
                            lookImage(photo).accessibilityLabel("Look \(index + 1)")
                        }
                        if model.summaryLoaded && model.isResultsRevealed && !model.isVoting {
                            Text("Look \(index + 1) · \(model.percent(for: photo.id))%")
                        } else {
                            Button("Vote for look \(index + 1)") { _ = model.vote(for: photo.id) {} }
                                .frame(minHeight: Theme.minTapSize)
                                .disabled(!model.canVote)
                                .accessibilityIdentifier("feed.vote.\(index)")
                        }
                    }
                }
            }
            if model.canRetract {
                Button("Undo vote") { model.retractVote {} }
                    .frame(minHeight: Theme.minTapSize)
            }
            if model.summaryLoadFailed {
                Button("Retry loading votes") { Task { await model.refreshSummary() } }
            }
            if let error = model.error { Text(error).font(Theme.caption) }
        }
        .buttonStyle(.plain)
        .font(Theme.bodyEmphasis)
        .task { await model.loadSummary() }
    }

    private func lookImage(_ photo: FitCheckPhoto) -> some View {
        Color.black.aspectRatio(3 / 4, contentMode: .fit)
            .overlay { RemoteImage(url: photo.imageUrl, contentMode: .fit) }
    }
}
