import SwiftUI

/// Feed post: author and prompt, auto-rotating photos, Like / Comment /
/// Send row, occasion and description. Voting controls live in Compare looks.
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
    let onVoteChange: (UUID?, Int) -> Void
    /// Opens the comment thread sheet.
    let onComment: () -> Void
    var onPhotoDisplay: (() -> Void)?

    @State private var comparing = false
    @State private var comparisonModel: ReelVoteModel?
    @State private var photoIndex = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Leaves room for the prompt and Compare looks around the photo.
    private static let photoAspectRatio: CGFloat = 5.0 / 6.0
    private static let descriptionLineLimit = 2
    /// Side inset for text; the photo itself spans the full width.
    private static let textInset: CGFloat = 16

    private var posterName: String { item.profiles?.nickname ?? "Someone" }
    private var title: String { PostCardContent.title(votePrompt: item.votePrompt, occasion: item.occasion) }
    private var photoURLs: [URL] { PostCardContent.photoURLs(item.fitCheckPhotos) }
    private var commentCount: Int { item.commentCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Text(title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("feed.postPrompt")
            }
            .padding(.horizontal, Self.textInset)
            TimelineView(.expiry(item.expiresAt)) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    if comparing, let comparisonModel {
                        compareButton
                        InlineLookComparison(model: comparisonModel, onOpen: onOpen, onVoteChange: onVoteChange)
                            .padding(.horizontal, Self.textInset)
                    } else {
                        photos(expired: isExpired(item.expiresAt))
                        if item.fitCheckPhotos.count >= 2 { compareButton }
                    }
                }
            }
            actionRow.padding(.horizontal, Self.textInset - 6)
            VStack(alignment: .leading, spacing: 6) { details }
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

    private var compareButton: some View {
        Button {
            if comparisonModel == nil { comparisonModel = ReelVoteModel(item: item, voterId: viewerId) }
            comparing.toggle()
        } label: {
            Label(comparing ? "Show carousel" : "Compare looks",
                  systemImage: comparing ? "rectangle" : "rectangle.split.2x1")
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.accentDeep)
                .frame(minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(InstantPressStyle())
        .padding(.horizontal, Self.textInset)
        .accessibilityIdentifier("feed.compare")
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
        let openPhoto = onOpen.map { open in { open(photoIndex) } }
        return PhotoCarousel(urls: photoURLs, currentIndex: $photoIndex, autoAdvance: !expired,
                             contentMode: .fit, accessibilityIdentifier: "feed-photo-carousel", onTap: openPhoto,
                             prioritizesSelectedPhoto: true, onPhotoDisplay: onPhotoDisplay)
            .aspectRatio(Self.photoAspectRatio, contentMode: .fit)
            .background(Color.black)
            .overlay { if expired { endedOverlay } }
            .clipped()
            .contentShape(Rectangle())
            .accessibilityAddTraits(openPhoto == nil ? [] : .isButton)
            .accessibilityActions {
                if let openPhoto {
                    Button(expired ? "See results" : "Open to vote", action: openPhoto)
                }
            }
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
    @ObservedObject var model: ReelVoteModel
    let onOpen: ((Int) -> Void)?
    let onVoteChange: (UUID?, Int) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var showsResults: Bool {
        model.summaryLoaded && model.isResultsRevealed && !model.isVoting && !model.isRetracting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(Theme.danger)
            }
            if model.summaryLoadFailed {
                Button("Retry loading votes") { Task { await model.refreshSummary() } }
                    .frame(minHeight: Theme.minTapSize)
            } else if !model.summaryLoaded {
                ProgressView("Loading voting…")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 14) {
                ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                    VStack(spacing: 6) {
                        if let onOpen {
                            Button { onOpen(index) } label: { lookImage(photo) }
                                .accessibilityLabel("Enlarge look \(index + 1)")
                        } else {
                            lookImage(photo)
                        }
                        lookAction(photo, number: index + 1)
                    }
                }
            }

            if model.isRetracting {
                ProgressView("Undoing your vote…")
                    .frame(minHeight: Theme.minTapSize)
            } else if model.canRetract {
                Button("Undo vote", systemImage: "arrow.uturn.backward") { undoVote() }
                    .frame(minHeight: Theme.minTapSize)
                    .foregroundStyle(Theme.accentDeep)
            }
        }
        .buttonStyle(.plain)
        .font(Theme.bodyEmphasis)
        .task(id: model.isEnded) { await model.loadSummary() }
        .onChange(of: model.error) { _, error in
            if let error { AccessibilityNotification.Announcement(error).post() }
        }
    }

    @ViewBuilder
    private func lookAction(_ photo: FitCheckPhoto, number: Int) -> some View {
        if showsResults {
            if model.myVote == photo.id {
                Label("Look \(number) · \(model.percent(for: photo.id))%", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accentDeep)
                    .accessibilityValue("Your vote")
                    .frame(minHeight: Theme.minTapSize)
            } else {
                Text("Look \(number) · \(model.percent(for: photo.id))%")
                    .frame(minHeight: Theme.minTapSize)
            }
        } else if model.isVoting, model.myVote == photo.id {
            ProgressView("Saving…")
                .frame(minHeight: Theme.minTapSize)
                .accessibilityIdentifier("feed.votePending")
        } else {
            Button {
                if model.vote(for: photo.id, onRecorded: {
                    onVoteChange(model.myVote, model.total)
                    if model.error == nil { AccessibilityNotification.Announcement("Vote recorded").post() }
                }) {
                    AccessibilityNotification.Announcement("Saving your vote").post()
                }
            } label: {
                Text("Vote for look \(number)")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
                    .padding(.horizontal, 8)
                    .foregroundStyle(model.canVote ? Theme.accentDeep : Theme.mutedForeground)
                    .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.smallRadius))
                    .contentShape(Rectangle())
            }
            .disabled(!model.canVote)
            .accessibilityIdentifier("feed.vote.\(number - 1)")
        }
    }

    private func undoVote() {
        model.retractVote {
            onVoteChange(model.myVote, model.total)
            AccessibilityNotification.Announcement("Vote undone. Pick again.").post()
        }
    }

    private func lookImage(_ photo: FitCheckPhoto) -> some View {
        Color.black.aspectRatio(3 / 4, contentMode: .fit)
            .overlay { RemoteImage(url: photo.imageUrl, contentMode: .fit) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius))
    }
}
