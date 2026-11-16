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

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.setTabBarHidden) private var setTabBarHidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: ReelVoteModel
    @StateObject private var commentsModel: VoteFanCommentsModel
    @State private var undoLookPosition: Int?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var isLiked = false
    @State private var likeCount: Int?
    @State private var isBookmarked = false
    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    private static let undoToastDuration: Duration = .seconds(5)

    init(item: FeedItemDTO, voterId: UUID, isFollowing: Bool, initialPhotoIndex: Int? = nil,
         onToggleFollow: @escaping (Bool) -> Void,
         onEvent: @escaping (String) -> Void, onImpression: @escaping () -> Void) {
        self.item = item
        self.voterId = voterId
        self.isFollowing = isFollowing
        self.onToggleFollow = onToggleFollow
        self.onEvent = onEvent
        self.onImpression = onImpression
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
            ScrollView {
                VStack(spacing: 14) {
                    fan
                    voteStatus
                    infoLine
                    actionRow
                    VoteFanCommentsPanel(model: commentsModel, photoId: model.currentPhoto?.id)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { commentInput }
            .overlay(alignment: .bottom) { undoToast.padding(.bottom, 80) }
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
                    .frame(width: 34, height: 34)
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
            Text("\(model.total)").font(Theme.font(.caption, weight: .black)).monospacedDigit()
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
                     myVote: model.myVote, onVote: castVote)
                .padding(.horizontal, -16)
        }
    }

    @ViewBuilder
    private var voteStatus: some View {
        if let error = model.error {
            Text(error).font(Theme.font(.caption, weight: .semibold)).foregroundStyle(Theme.danger)
        } else if model.isEnded {
            Text("Voting ended").font(Theme.font(.footnote, weight: .bold)).foregroundStyle(Theme.mutedForeground)
        } else if model.isCreator {
            Text("This is your Fit-Check").font(Theme.font(.footnote, weight: .bold)).foregroundStyle(Theme.mutedForeground)
        } else if model.canVote {
            Label(model.isFirstTimeVoter ? "Hold the centre photo to vote · swipe for the next look" : "Hold to vote",
                  systemImage: "hand.tap")
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
            HStack(spacing: 8) {
                AvatarView(url: item.profiles?.avatarUrl, nickname: item.profiles?.nickname, size: 30, ringed: true)
                Text(nickname).font(Theme.font(.subheadline, weight: .bold)).lineLimit(1)
                Text(handle).font(Theme.font(.caption, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                Spacer(minLength: 0)
                if !model.isCreator { followPill }
            }
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

    private var followPill: some View {
        Button(isFollowing ? "Following" : "+ Follow") { onToggleFollow(!isFollowing) }
            .font(Theme.font(.caption, weight: .bold))
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
            BookmarkButton(isBookmarked: isBookmarked) { wantsSave in
                if wantsSave { try await API.bookmarkFitCheck(id: item.id, userId: voterId) }
                else { try await API.unbookmarkFitCheck(id: item.id, userId: voterId) }
            }
            ShareLinkButton(fitCheckId: item.id, summary: title)
                .simultaneousGesture(TapGesture().onEnded { onEvent("share") })
            Spacer(minLength: 0)
        }
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

    private func castVote() {
        let started = model.voteForCurrentLook { appState.contentDidChange() }
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
        Haptics.impact(.light)
        model.retractVote { appState.contentDidChange() }
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
                    .foregroundStyle(Theme.accent)
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
