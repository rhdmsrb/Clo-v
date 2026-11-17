import SwiftUI

/// Feed post: author, prompt title, auto-rotating photos, a vote row (one button
/// per look, then the results), Like / Comment / Send row, occasion and
/// description. Votes are cast on the card; tapping the photos opens the full
/// vote screen.
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
    let onOpen: (_ photoIndex: Int) -> Void
    /// Opens the comment thread sheet.
    let onComment: () -> Void
    /// The viewer's vote on this post once the server confirmed it (`nil` after an undo).
    var onVoteChange: (UUID?) -> Void = { _ in }

    @State private var photoIndex = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Slightly shorter than 4:5 so the action row and title come into view sooner.
    private static let photoAspectRatio: CGFloat = 5.0 / 6.0
    private static let descriptionLineLimit = 2
    /// Side inset for text; the photo itself spans the full width.
    private static let textInset: CGFloat = 16

    private var posterName: String { item.profiles?.nickname ?? "Someone" }
    private var title: String { PostCardContent.title(votePrompt: item.votePrompt, occasion: item.occasion) }
    private var photoURLs: [URL] { PostCardContent.photoURLs(item.fitCheckPhotos) }
    private var commentCount: Int { item.fitCheckComments.count }

    var body: some View {
        // Photo first: author, full-bleed photo, actions, then one title line.
        // No card surface or shadow, so the clothes carry the screen.
        VStack(alignment: .leading, spacing: 10) {
            header.padding(.horizontal, Self.textInset)
            // One timeline per card, ticking once at expiry.
            TimelineView(.expiry(item.expiresAt)) { _ in
                photos(expired: isExpired(item.expiresAt))
            }
            FeedCardVoteSection(item: item, viewerId: viewerId, highlightedIndex: photoIndex,
                                onVoteChange: onVoteChange)
                .padding(.horizontal, Self.textInset)
            actionRow.padding(.horizontal, Self.textInset - 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                details
            }
            .padding(.horizontal, Self.textInset)
        }
        .fitCheckContextMenu(
            fitCheckId: item.id, creatorId: item.creatorId, posterName: posterName, viewerId: viewerId,
            isFollowing: isFollowing, onToggleFollow: showsFollow ? onToggleFollow : nil
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(posterName)’s Fit-Check")
        .accessibilityIdentifier("feed-post-card")
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

    private func photos(expired: Bool) -> some View {
        PhotoCarousel(urls: photoURLs, currentIndex: $photoIndex, autoAdvance: !expired,
                      accessibilityIdentifier: "feed-photo-carousel", onTap: { onOpen(photoIndex) })
            .aspectRatio(Self.photoAspectRatio, contentMode: .fit)
            .overlay { if expired { endedOverlay } }
            .clipped()
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: expired ? "See results" : "Open to vote") { onOpen(photoIndex) }
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
