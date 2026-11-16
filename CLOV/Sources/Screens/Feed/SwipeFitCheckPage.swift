import SwiftUI

/// One full-screen Fit-Check. Swipe sideways to browse its photos; press and
/// hold (~0.6s) to vote for the photo on screen.
struct SwipeFitCheckPage: View {
    let item: FeedItemDTO
    let voterId: UUID
    let isFollowing: Bool
    let onToggleFollow: (Bool) -> Void
    let onEvent: (String) -> Void
    let onImpression: () -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: ReelVoteModel
    @StateObject private var celebration = CelebrationState()
    /// Brief "Voted · Undo" toast shown after a vote; nil when hidden.
    @State private var undoLookPosition: Int?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var isDescriptionExpanded = false
    @State private var showComments = false
    @State private var isLiked = false
    @State private var likeCount: Int?
    @State private var isBookmarked = false
    @State private var showingReportReasons = false
    @State private var showingBlockConfirmation = false
    @State private var safetyMessage: String?

    private static let bottomInset: CGFloat = 112
    private static let lookIndicatorTopPadding: CGFloat = 112
    private static let undoToastDuration: Duration = .seconds(5)
    private static let railWidth: CGFloat = 56
    private static let collapsedDescriptionLines = 2

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
        _likeCount = State(initialValue: item.likeCount)
    }

    private var nickname: String { item.profiles?.nickname ?? "Someone" }
    /// The @handle shown on the overlay: the account code, else the nickname.
    private var handle: String { PostCardContent.handle(accountCode: item.profiles?.accountCode, nickname: item.profiles?.nickname) }
    private var canFollow: Bool { !model.isCreator }
    private var title: String? {
        [item.votePrompt, item.occasion].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    /// The photo on screen's own description, falling back to the post caption.
    private var photoDescription: String? {
        PostCardContent.overlayDescription(photoDescription: model.currentPhoto?.description, caption: item.caption)
    }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .bottomLeading) {
                photoLayer
                Theme.photoScrim.allowsHitTesting(false)
                HStack(alignment: .bottom, spacing: 18) {
                    infoColumn
                    actionRail
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.bottom, Self.bottomInset)
            }
            .overlay {
                if celebration.burstId != nil, !reduceMotion {
                    ConfettiBurst().id(celebration.burstId)
                }
            }
            .overlay(alignment: .top) { lookIndicator }
            .overlay(alignment: .bottom) { undoToast.padding(.bottom, Self.bottomInset + 8) }
            .onAppear(perform: onImpression)
        }
        .accessibilityAction(named: "Undo vote") { undoVote() }
        .accessibilityAction(named: "Show next look") { model.showLook(step: 1) }
        .sensoryFeedback(.selection, trigger: model.lookIndex)
        .onChange(of: model.error) { _, newError in
            // Async vote failures surface here; announce so non-visual users hear them.
            guard newError != nil else { return }
            AccessibilityNotification.Announcement("Couldn’t record your vote. Try again.").post()
        }
        .sheet(isPresented: $showComments) {
            CommentThreadSheet(fitCheckId: item.id, photoURLs: model.photos.map(\.imageUrl),
                               voterId: voterId, canComment: !model.isEnded)
                .environmentObject(appState)
        }
        .confirmationDialog("Why are you reporting this?", isPresented: $showingReportReasons, titleVisibility: .visible) {
            ForEach(ReportReason.all) { reason in
                Button(reason.title) { Task { await report(reason: reason.value) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Block this creator?", isPresented: $showingBlockConfirmation, titleVisibility: .visible) {
            Button("Block creator", role: .destructive) { Task { await blockCreator() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won’t see their Fit-Checks anymore.")
        }
        .alert("Thanks", isPresented: Binding(get: { safetyMessage != nil }, set: { if !$0 { safetyMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(safetyMessage ?? "") }
        .task { await loadEngagement() }
    }

    // MARK: Photo and hold-to-vote

    private var lookBinding: Binding<Int> {
        Binding(get: { model.lookIndex }, set: { model.setLook($0) })
    }

    @ViewBuilder
    private var photoLayer: some View {
        if model.photos.isEmpty {
            Theme.muted
        } else {
            PhotoCarousel(urls: model.photos.compactMap { URL(string: $0.imageUrl) },
                          currentIndex: lookBinding, contentMode: .fill,
                          accessibilityIdentifier: "reel-photo-carousel")
                .holdToVote(isEnabled: model.canVote) { castVote() }
        }
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

    @ViewBuilder
    private var lookIndicator: some View {
        if model.photos.count > 1 {
            HStack(spacing: 6) {
                ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, _ in
                    Capsule()
                        .fill(index == model.lookIndex ? Color.white : Color.white.opacity(0.4))
                        .frame(width: index == model.lookIndex ? 22 : 8, height: 4)
                }
            }
            .padding(.top, Self.lookIndicatorTopPadding)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Look \(model.lookIndex + 1) of \(model.photos.count)")
        }
    }

    // MARK: Info

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                AvatarView(url: item.profiles?.avatarUrl, nickname: item.profiles?.nickname, size: 30, ringed: true)
                Text(handle).font(Theme.font(.subheadline, weight: .bold))
                if canFollow { followPill }
            }
            if let title {
                Text(title).font(Theme.font(.headline, weight: .bold)).lineLimit(2)
            }
            descriptionText
            resultsChip
            voteStatus
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private var descriptionText: some View {
        if let photoDescription {
            Text(photoDescription)
                .font(Theme.font(.subheadline, weight: .medium))
                .lineLimit(isDescriptionExpanded ? nil : Self.collapsedDescriptionLines)
                .onTapGesture { withAnimation(reduceMotion ? nil : .snappy) { isDescriptionExpanded.toggle() } }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(isDescriptionExpanded ? "Collapses the description" : "Expands the description")
        }
    }

    /// VOTE # and the per-photo split, blurred until the viewer has voted,
    /// created the post, or voting ended.
    private var resultsChip: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text("VOTES")
                RevealCounter(target: model.total, isRevealed: model.isResultsRevealed)
            }
            .font(Theme.font(.caption, weight: .black))
            ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                lookResult(photo, index: index, leading: leadingIds.contains(photo.id))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.black.opacity(0.45), in: Capsule())
        .blurReveal(isRevealed: model.isResultsRevealed)
        .accessibilityElement(children: .combine)
    }

    private func lookResult(_ photo: FitCheckPhoto, index: Int, leading: Bool) -> some View {
        HStack(spacing: 3) {
            if leading {
                Image(systemName: "crown.fill").foregroundStyle(Theme.win)
                    .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : model.isResultsRevealed)
                    .accessibilityHidden(true)
            }
            Text("Look \(photo.position)")
            RevealCounter(target: model.percent(for: photo.id), isRevealed: model.isResultsRevealed, style: .percent,
                          delay: reduceMotion ? 0 : Double(index) * 0.12)
        }
        .font(Theme.font(.caption, weight: photo.id == model.myVote ? .black : .medium))
        .accessibilityElement(children: .combine)
        .accessibilityValue(leading ? "leading" : "")
    }

    private var photoIds: [UUID] { model.photos.map(\.id) }

    private var leadingIds: Set<UUID> {
        model.isResultsRevealed ? VoteReveal.leadingIds(photoIds: photoIds, counts: model.counts) : []
    }

    /// Runs once the server confirmed the vote; the success haptic already played in the model.
    private func voteRecorded() {
        appState.contentDidChange()
        guard model.error == nil, !reduceMotion,
              VoteReveal.shouldCelebrate(myVote: model.myVote, photoIds: photoIds, counts: model.counts, total: model.total)
        else { return }
        celebration.celebrate()
    }

    @ViewBuilder
    private var voteStatus: some View {
        if let myVote = model.myVote, let insight = model.insight {
            VStack(alignment: .leading, spacing: 4) {
                Text("You picked look \(model.photos.first { $0.id == myVote }?.position ?? 1) · \(model.percent(for: myVote))%")
                    .font(Theme.font(.footnote, weight: .black))
                Text(insight).font(Theme.font(.caption, weight: .medium))
                if let summary = model.streak.summary() {
                    Label(summary, systemImage: "flame.fill").font(Theme.font(.caption, weight: .bold)).foregroundStyle(Theme.accent)
                }
            }
            .padding(10)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityElement(children: .combine)
        } else if let error = model.error {
            Text(error).font(Theme.font(.caption, weight: .semibold)).foregroundStyle(Theme.danger)
        } else if model.canVote {
            holdHint
        }
    }

    private var holdHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap").accessibilityHidden(true)
            Text(model.isFirstTimeVoter ? "Hold to vote · swipe for the next look" : "Hold to vote")
        }
        .font(Theme.font(.caption, weight: .bold))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(0.18), in: Capsule())
        .accessibilityHidden(true)
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

    // MARK: Action rail

    private var actionRail: some View {
        VStack(spacing: 14) {
            LikeButton(isLiked: isLiked, count: likeCount) { wantsLike in
                if wantsLike { try await API.likeFitCheck(id: item.id, userId: voterId) }
                else { try await API.unlikeFitCheck(id: item.id, userId: voterId) }
                onEvent(wantsLike ? "like" : "unlike")
            }
            Button { showComments = true; onEvent("open_comments") } label: { railIcon("bubble.right", count: item.fitCheckComments.count) }
                .buttonStyle(.plain)
                .accessibilityLabel("Comments, \(item.fitCheckComments.count)")
            BookmarkButton(isBookmarked: isBookmarked) { wantsSave in
                if wantsSave { try await API.bookmarkFitCheck(id: item.id, userId: voterId) }
                else { try await API.unbookmarkFitCheck(id: item.id, userId: voterId) }
            }
            sendButton
            if !model.isCreator { overflowMenu }
        }
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        .frame(width: Self.railWidth)
    }

    @ViewBuilder
    private var sendButton: some View {
        if let url = ShareURL.make(fitCheckId: item.id) {
            ShareLink(item: url) { railIcon("paperplane", count: nil) }
                .simultaneousGesture(TapGesture().onEnded { onEvent("share") })
                .accessibilityLabel("Send")
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button("Report Fit-Check", systemImage: "flag") { showingReportReasons = true }
            Button("Block creator", systemImage: "person.slash", role: .destructive) { showingBlockConfirmation = true }
        } label: {
            railIcon("ellipsis", count: nil)
        }
        .accessibilityLabel("Report or block")
    }

    private func railIcon(_ symbol: String, count: Int?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if let count { Text("\(count)").font(Theme.font(.footnote, weight: .semibold)).monospacedDigit() }
        }
        .foregroundStyle(.white)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: Engagement and safety

    /// Likes and bookmarks live in tables that may not exist yet; failures leave the defaults.
    private func loadEngagement() async {
        let ids = [item.id]
        if let liked = try? await API.fetchLikedFitCheckIDs(among: ids, userId: voterId) { isLiked = liked.contains(item.id) }
        if let saved = try? await API.fetchBookmarkedFitCheckIDs(among: ids, userId: voterId) { isBookmarked = saved.contains(item.id) }
        await refreshLikeCount()
    }

    /// Keeps the previous count when the fetch fails or the post is unknown.
    private func refreshLikeCount() async {
        do {
            if let count = try await API.fetchLikeCount(id: item.id) { likeCount = count }
        } catch {
            Log.app.error("Like count fetch failed: \(error.localizedDescription)")
        }
    }

    private func report(reason: String) async {
        do {
            try await API.reportFitCheck(id: item.id, reason: reason)
            safetyMessage = "Your report was submitted for review."
        } catch {
            safetyMessage = "We couldn’t submit the report. Please try again."
        }
    }

    private func blockCreator() async {
        do {
            try await API.blockUser(id: item.creatorId)
            safetyMessage = "Creator blocked. Their content will be removed from your feed after refresh."
        } catch {
            safetyMessage = "We couldn’t block this creator. Please try again."
        }
    }
}
