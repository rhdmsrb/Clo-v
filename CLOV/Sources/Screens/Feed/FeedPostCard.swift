import SwiftUI

/// Feed post: author, prompt title, auto-rotating photos, Like / Comment /
/// Send row, occasion and description. Shows no vote counts; tapping the
/// photos opens the vote screen.
struct FeedPostCard: View {
    let item: FeedItemDTO
    let isLiked: Bool
    let isFollowing: Bool
    let showsFollow: Bool
    let onToggleFollow: (Bool) -> Void
    let onLike: (Bool) async throws -> Void
    /// Opens the vote screen on the photo currently showing in the carousel.
    let onOpen: (_ photoIndex: Int) -> Void
    /// Opens the comment thread sheet.
    let onComment: () -> Void

    @State private var photoIndex = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let photoAspectRatio: CGFloat = 4.0 / 5.0
    private static let descriptionLineLimit = 3

    private var posterName: String { item.profiles?.nickname ?? "Someone" }
    private var title: String { PostCardContent.title(votePrompt: item.votePrompt, occasion: item.occasion) }
    private var photoURLs: [URL] { PostCardContent.photoURLs(item.fitCheckPhotos) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(title)
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            // One timeline per card, ticking once at expiry.
            TimelineView(.expiry(item.expiresAt)) { _ in
                photos(expired: isExpired(item.expiresAt))
            }
            actionRow
            details
        }
        .elevatedCard(radius: Theme.cardRadius, padding: 14)
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
                if showsFollow { followButton }
            }
        } else {
            HStack(spacing: 10) {
                authorRow(nameLineLimit: 1)
                Spacer(minLength: 0)
                if showsFollow { followButton }
            }
        }
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
                      accessibilityIdentifier: "feed-photo-carousel")
            .aspectRatio(Self.photoAspectRatio, contentMode: .fit)
            .overlay { if expired { endedOverlay } }
            .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { onOpen(photoIndex) }
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
                rowLabel("Comment", systemImage: "bubble.left")
            }
            .buttonStyle(InstantPressStyle())
            .accessibilityLabel("Comments")
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

    private func rowLabel(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text).font(Theme.font(.footnote, weight: .semibold)).lineLimit(1)
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
                .foregroundStyle(Theme.accentDeep)
                .lineLimit(1)
                .accessibilityLabel("Tags: \(tags.joined(separator: ", "))")
        }
    }

    @ViewBuilder
    private var details: some View {
        if let occasion = item.occasion, !occasion.isEmpty {
            Text(occasion)
                .font(Theme.micro)
                .foregroundStyle(Theme.accentDeep)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Theme.accentTint, in: Capsule(style: .continuous))
        }
        if let caption = item.caption, !caption.isEmpty {
            Text(caption)
                .font(Theme.font(.subheadline))
                .foregroundStyle(Theme.ink)
                .lineLimit(Self.descriptionLineLimit)
        }
        tagsRow
    }
}
