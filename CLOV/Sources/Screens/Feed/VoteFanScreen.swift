import SwiftUI

/// "Vote screen 2": a cover-flow fan of photos (hold the centred one to vote),
/// a compact info line, and a comments panel for the selected photo.
struct VoteFanScreen: View {
    let item: FeedItemDTO
    let voterId: UUID
    let isFollowing: Bool
    let onToggleFollow: (Bool) -> Void
    let onEvent: (String) -> Void
    let onImpression: () -> Void
    /// Reports the viewer's vote and the new total so the feed card can update in place.
    let onVoteChange: ((UUID?, Int) -> Void)?

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.setTabBarHidden) private var setTabBarHidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var model: ReelVoteModel
    @StateObject private var commentsModel: VoteFanCommentsModel
    @StateObject private var celebration = CelebrationState()
    @State private var undoLookPosition: Int?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var isLiked = false
    @State private var likeCount: Int?
    @State private var isBookmarked = false
    @State private var draft = ""
    @FocusState private var isInputFocused: Bool
    /// Bumped by the comment button; the scroll view jumps to the comments panel.
    @State private var commentsScrollRequest = 0
    @ScaledMetric(relativeTo: .body) private var backButtonSize: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var authorAvatarSize: CGFloat = 30

    private static let undoToastDuration: Duration = .seconds(5)
    private static let commentsAnchor = "voteFanCommentsAnchor"
    /// The scaled author avatar stops growing here so it never crowds the name.
    private static let maxAuthorAvatarSize: CGFloat = 44

    init(item: FeedItemDTO, voterId: UUID, isFollowing: Bool, initialPhotoIndex: Int? = nil,
         onToggleFollow: @escaping (Bool) -> Void,
         onEvent: @escaping (String) -> Void, onImpression: @escaping () -> Void,
         onVoteChange: ((UUID?, Int) -> Void)? = nil) {
        self.item = item
        self.voterId = voterId
        self.isFollowing = isFollowing
        self.onToggleFollow = onToggleFollow
        self.onEvent = onEvent
        self.onImpression = onImpression
        self.onVoteChange = onVoteChange
        _model = StateObject(wrappedValue: ReelVoteModel(item: item, voterId: voterId, initialLook: initialPhotoIndex))
        _commentsModel = StateObject(wrappedValue: VoteFanCommentsModel(fitCheckId: item.id))
        _likeCount = State(initialValue: item.likeCount)
    }

    private var nickname: String { item.profiles?.nickname ?? "Someone" }
    private var handle: String { PostCardContent.handle(accountCode: item.profiles?.accountCode, nickname: item.profiles?.nickname) }
    private var title: String? {
        [item.votePrompt, item.occasion].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    private var photoDescription: String? {
        PostCardContent.overlayDescription(photoDescription: model.currentPhoto?.description, caption: item.caption)
    }
    private var lookBinding: Binding<Int> {
        Binding(get: { model.lookIndex }, set: { model.setLook($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        fan
                        voteStatus
                        infoLine
                        actionRow
                        VoteFanCommentsPanel(model: commentsModel, photoId: model.currentPhoto?.id)
                            .id(Self.commentsAnchor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: commentsScrollRequest) { _, _ in
                    withAnimation(reduceMotion ? nil : Theme.settle) { proxy.scrollTo(Self.commentsAnchor, anchor: .top) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { commentInput }
                .overlay(alignment: .bottom) { undoToast.padding(.bottom, 80) }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        // A container element, so the children keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voteFanScreen")
        .accessibilityActions {
            if model.canRetract { Button("Undo vote") { undoVote() } }
        }
        .sensoryFeedback(.selection, trigger: model.lookIndex)
        .onChange(of: model.error) { _, newError in
            guard newError != nil else { return }
            AccessibilityNotification.Announcement("Couldn’t record your vote. Try again.").post()
        }
        .onAppear {
            setTabBarHidden(true)
            onImpression()
        }
        .onDisappear {
            setTabBarHidden(false)
            undoDismissTask?.cancel()
            celebration.cancel()
        }
        .task { await commentsModel.load() }
        .task { await model.loadSummary() }
        .task { await loadEngagement() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: backButtonSize, height: backButtonSize)
                    .background(.black.opacity(0.55), in: Circle())
                    .frame(minWidth: FeedLayout.minHitSize, minHeight: FeedLayout.minHitSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("reelBackButton")
            Spacer()
            totalChip
            Spacer()
            if model.isCreator {
                Color.clear.frame(width: FeedLayout.minHitSize, height: FeedLayout.minHitSize)
            } else {
                VoteFanSafetyMenu(fitCheckId: item.id, creatorId: item.creatorId)
            }
        }
        .padding(.horizontal, 6)
    }

    /// "Vote #" with the count blurred until results are revealed.
    private var totalChip: some View {
        HStack(spacing: 6) {
            Text("Vote #").font(Theme.font(.caption, weight: .black))
            RevealCounter(target: model.total, isRevealed: model.isResultsRevealed)
                .font(Theme.font(.caption, weight: .black))
                .blurReveal(isRevealed: model.isResultsRevealed)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.white.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("voteFanTotalChip")
    }

    // MARK: Fan and status

    @ViewBuilder
    private var fan: some View {
        if model.photos.isEmpty {
            Theme.muted.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        } else {
            PhotoFan(photos: model.photos, selection: lookBinding, canVote: model.canVote,
                     isResultsRevealed: model.isResultsRevealed, percent: { model.percent(for: $0) },
                     myVote: model.myVote, leadingIds: leadingIds, onVote: castVote)
                .padding(.horizontal, -16)
                .overlay {
                    if celebration.burstId != nil, !reduceMotion {
                        ConfettiBurst().id(celebration.burstId)
                    }
                }
        }
    }

    @ViewBuilder
    private var voteStatus: some View {
        if model.summaryLoadFailed && !model.summaryLoaded {
            Button("Couldn’t load voting. Tap to retry") { Task { await model.loadSummary() } }
                .accessibilityIdentifier("vote.summaryRetry")
        } else if !model.summaryLoaded {
            ProgressView("Loading voting…").accessibilityIdentifier("vote.summaryLoading")
        } else if let error = model.error {
            Text(error).font(Theme.font(.caption, weight: .semibold)).foregroundStyle(Theme.danger)
        } else if model.isEnded {
            Text("Voting ended").font(Theme.font(.footnote, weight: .bold)).foregroundStyle(Theme.mutedForeground)
        } else if model.isCreator {
            Text("This is your Fit-Check").font(Theme.font(.footnote, weight: .bold)).foregroundStyle(Theme.mutedForeground)
        } else if model.canVote, model.isFirstTimeVoter {
            // A teaching hint for the first vote only; after that the gesture
            // is known and the pill would just be chrome over the photos.
            Label("Hold the centre photo to vote · swipe for the next look", systemImage: "hand.tap")
                .font(Theme.font(.caption, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white.opacity(0.18), in: Capsule())
                .accessibilityHidden(true)
        }
    }

    // MARK: Info and actions

    private var infoLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            authorRow
            if let title {
                Text(title).font(Theme.font(.headline, weight: .bold)).lineLimit(2)
            }
            if let photoDescription {
                Text(photoDescription).font(Theme.font(.subheadline, weight: .medium)).lineLimit(3)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Author and Follow on one line; at accessibility text sizes the pill drops
    /// under the name so neither truncates or wraps.
    @ViewBuilder
    private var authorRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                authorIdentity
                if !model.isCreator { followPill }
            }
        } else {
            HStack(spacing: 8) {
                authorIdentity
                Spacer(minLength: 0)
                if !model.isCreator { followPill }
            }
        }
    }

    private var authorIdentity: some View {
        HStack(spacing: 8) {
            AvatarView(url: item.profiles?.avatarUrl, nickname: item.profiles?.nickname,
                       size: min(authorAvatarSize, Self.maxAuthorAvatarSize), ringed: true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) { nameText; handleText }
            } else {
                HStack(spacing: 8) { nameText; handleText }
            }
        }
    }

    private var nameText: some View {
        Text(nickname).font(Theme.font(.subheadline, weight: .bold)).lineLimit(1)
    }

    private var handleText: some View {
        Text(handle).font(Theme.font(.caption, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
    }

    private var followPill: some View {
        Button(isFollowing ? "Following" : "+ Follow") { onToggleFollow(!isFollowing) }
            .font(Theme.font(.caption, weight: .bold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isFollowing ? Color.white : Theme.accentForeground)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isFollowing ? .white.opacity(0.18) : Theme.accent, in: Capsule())
            .frame(minHeight: FeedLayout.minHitSize)
            .contentShape(Rectangle())
            .accessibilityLabel("Follow \(nickname)")
            .accessibilityValue(isFollowing ? "Following" : "Not following")
            .accessibilityAddTraits(.isToggle)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            LikeButton(isLiked: isLiked, count: likeCount) { wantsLike in
                if wantsLike { try await API.likeFitCheck(id: item.id, userId: voterId) }
                else { try await API.unlikeFitCheck(id: item.id, userId: voterId) }
                onEvent(wantsLike ? "like" : "unlike")
            }
            commentButton
            BookmarkButton(isBookmarked: isBookmarked) { wantsSave in
                if wantsSave { try await API.bookmarkFitCheck(id: item.id, userId: voterId) }
                else { try await API.unbookmarkFitCheck(id: item.id, userId: voterId) }
            }
            ShareLinkButton(fitCheckId: item.id, summary: title)
                .simultaneousGesture(TapGesture().onEnded { onEvent("share") })
            Spacer(minLength: 0)
        }
    }

    /// Comments for the photo on screen, same filter as the panel below.
    private var visibleCommentCount: Int {
        PhotoComments.visible(commentsModel.comments, photoId: model.currentPhoto?.id).count
    }

    /// Scrolls to the comments so they are one tap away from the photos.
    private var commentButton: some View {
        Button { commentsScrollRequest += 1 } label: {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left")
                if visibleCommentCount > 0 {
                    Text("\(visibleCommentCount)").font(Theme.font(.footnote, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(minWidth: FeedLayout.minHitSize, minHeight: FeedLayout.minHitSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(InstantPressStyle())
        .accessibilityLabel("Comments")
        .accessibilityValue(visibleCommentCount == 1 ? "1 comment" : "\(visibleCommentCount) comments")
        .accessibilityHint("Jumps to the comments")
        .accessibilityIdentifier("voteFanCommentButton")
    }

    // MARK: Comments input

    private var commentInput: some View {
        VoteFanCommentInput(draft: $draft, avatarUrl: appState.profile?.avatarUrl, nickname: appState.profile?.nickname,
                            canComment: !model.isEnded, isPosting: commentsModel.isPosting,
                            postError: commentsModel.postError, isFocused: $isInputFocused, onSend: sendComment)
    }

    private func sendComment() {
        let body = draft
        let photoId = model.currentPhoto?.id
        Task {
            let posted = await commentsModel.post(body: body, photoId: photoId, commenterId: voterId)
            guard posted else { return }
            draft = ""
            isInputFocused = false
            appState.contentDidChange()
        }
    }

    // MARK: Voting

    private var photoIds: [UUID] { model.photos.map(\.id) }

    /// Crowns only show once results are visible.
    private var leadingIds: Set<UUID> {
        model.isResultsRevealed ? VoteReveal.leadingIds(photoIds: photoIds, counts: model.counts) : []
    }

    /// Runs once the server has confirmed the vote. The success haptic already played in the model.
    private func voteRecorded() {
        refreshFeedVote()
        guard model.error == nil, !reduceMotion,
              VoteReveal.shouldCelebrate(myVote: model.myVote, photoIds: photoIds, counts: model.counts, total: model.total)
        else { return }
        celebration.celebrate()
    }

    /// Updates the feed card directly when it can; otherwise reloads the home feed.
    private func refreshFeedVote() {
        onVoteChange?(model.myVote, model.total)
        appState.contentDidChange(reloadHomeFeed: onVoteChange == nil)
    }

    private func castVote() {
        let started = model.voteForCurrentLook { voteRecorded() }
        guard started, let position = model.currentPhoto?.position else {
            AccessibilityNotification.Announcement("Vote not recorded").post()
            return
        }
        AccessibilityNotification.Announcement("Vote recorded, results shown").post()
        showUndoToast(for: position)
    }

    private func undoVote() {
        hideUndoToast()
        guard model.canRetract else { return }
        celebration.cancel()
        Haptics.impact(.light)
        model.retractVote { refreshFeedVote() }
        AccessibilityNotification.Announcement("Vote undone. Pick again.").post()
    }

    private func showUndoToast(for position: Int) {
        undoDismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .snappy) { undoLookPosition = position }
        undoDismissTask = Task {
            try? await Task.sleep(for: Self.undoToastDuration)
            guard !Task.isCancelled else { return }
            hideUndoToast()
        }
    }

    private func hideUndoToast() {
        undoDismissTask?.cancel()
        withAnimation(reduceMotion ? nil : .snappy) { undoLookPosition = nil }
    }

    @ViewBuilder
    private var undoToast: some View {
        if let position = undoLookPosition {
            HStack(spacing: 12) {
                Label("Voted Look \(position)", systemImage: "checkmark.circle.fill")
                    .font(Theme.font(.subheadline, weight: .bold))
                Button("Undo", action: undoVote)
                    .font(Theme.font(.subheadline, weight: .black))
                    .foregroundStyle(.white)
                    .frame(minHeight: FeedLayout.minHitSize)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .background(.black.opacity(0.7), in: Capsule())
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: Engagement

    /// Likes and bookmarks live in tables that may not exist yet; failures leave the defaults.
    private func loadEngagement() async {
        let ids = [item.id]
        if let liked = try? await API.fetchLikedFitCheckIDs(among: ids, userId: voterId) { isLiked = liked.contains(item.id) }
        if let saved = try? await API.fetchBookmarkedFitCheckIDs(among: ids, userId: voterId) { isBookmarked = saved.contains(item.id) }
        do {
            if let count = try await API.fetchLikeCount(id: item.id) { likeCount = count }
        } catch {
            Log.app.error("Like count fetch failed: \(error.localizedDescription)")
        }
    }
}
