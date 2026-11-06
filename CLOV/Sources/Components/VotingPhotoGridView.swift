import SwiftUI

struct VotingPhotoGridView: View {
    @EnvironmentObject private var appState: AppState
    private let incomingCounts: [UUID: Int]
    private let incomingTotal: Int
    private let incomingVote: UUID?

    let fitCheckId: UUID
    let creatorId: UUID
    let status: String
    let photos: [FitCheckPhoto]
    let voterId: UUID
    let prompt: String?
    let expiresAt: Date?

    @State private var counts: [UUID: Int]
    @State private var total: Int
    @State private var myVote: UUID?
    @State private var error: String?
    @State private var isVoting = false
    @State private var isRetracting = false
    @State private var showsReactions = false
    @State private var isSendingReaction = false
    @State private var commentPhotoId: UUID?
    @State private var expandedPhoto: FitCheckPhoto?
    /// A tapped photo waits here until the voter confirms, so a stray tap never casts a vote.
    @State private var photoAwaitingConfirmation: FitCheckPhoto?
    @State private var reactionMessage: String?
    @State private var streak = VoteStreak()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set (to a fresh id) when the voter backs the leading look; drives the confetti and its haptic.
    @State private var celebration: UUID?

    private static let minVotesToCelebrate = 2

    /// When the parent card owns the expiry clock it passes the current tick
    /// here; otherwise the grid runs its own timeline.
    let clock: Date?
    /// Swap the grid for `VotingEndedView` once `expiresAt` passes. The grid
    /// (and the sheet/cover attached to it) stays mounted across the swap.
    let showsEndedStateWhenExpired: Bool
    /// Only a public post's result may be exported by someone other than its
    /// creator. Defaults to false so an unknown audience fails closed.
    let isPublicPost: Bool

    init(fitCheckId: UUID, creatorId: UUID, status: String, photos: [FitCheckPhoto],
         voteCounts: [UUID: Int], totalVotes: Int, myVote: UUID?, voterId: UUID, expiresAt: Date? = nil, prompt: String? = nil,
         clock: Date? = nil, showsEndedStateWhenExpired: Bool = false, isPublicPost: Bool = false) {
        self.isPublicPost = isPublicPost
        self.fitCheckId = fitCheckId
        self.creatorId = creatorId
        self.status = status
        self.photos = photos.sorted { $0.position < $1.position }
        self.voterId = voterId
        self.prompt = prompt
        self.expiresAt = expiresAt
        self.clock = clock
        self.showsEndedStateWhenExpired = showsEndedStateWhenExpired
        incomingCounts = voteCounts
        incomingTotal = totalVotes
        incomingVote = myVote
        _counts = State(initialValue: voteCounts)
        _total = State(initialValue: totalVotes)
        _myVote = State(initialValue: myVote)
    }

    // Evaluated against the current time on every timeline tick (and again at
    // vote time), so a card left on screen stops accepting votes once it expires.
    private var canVote: Bool { status == "live" && creatorId != voterId && !isExpired(expiresAt) }
    private var revealed: Bool { myVote != nil || !canVote }
    /// A voter (not the creator) who has already picked a look.
    private var hasVoted: Bool { myVote != nil && creatorId != voterId }
    private var showsShare: Bool { revealed && total > 0 && canShareResult }
    private var leadingCount: Int { counts.values.max() ?? 0 }

    var body: some View {
        clockedContent
        .onChange(of: incomingCounts) { _, _ in syncVotes() }
        .onChange(of: incomingTotal) { _, _ in syncVotes() }
        .onChange(of: incomingVote) { _, _ in syncVotes() }
        .sheet(isPresented: Binding(get: { commentPhotoId != nil }, set: { if !$0 { commentPhotoId = nil } })) {
            if let commentPhotoId {
                CommentSheet(fitCheckId: fitCheckId, photoId: commentPhotoId, voterId: voterId) {
                    self.commentPhotoId = nil
                }
            }
        }
        .fullScreenCover(item: $expandedPhoto) { photo in
            PhotoZoomView(photo: photo)
        }
        .confirmationDialog(
            photoAwaitingConfirmation.map { "Vote for Look \($0.position)?" } ?? "Confirm your vote",
            isPresented: Binding(get: { photoAwaitingConfirmation != nil }, set: { if !$0 { photoAwaitingConfirmation = nil } }),
            titleVisibility: .visible,
            presenting: photoAwaitingConfirmation
        ) { photo in
            Button("Vote for Look \(photo.position)") { vote(on: photo.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You can change your vote while voting is open.")
        }
        .task {
            Haptics.prepare()
            streak = VoteStreakStore.load(for: voterId)
        }
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: celebration) { _, new in new != nil }
    }

    // Re-reads `canVote`/`revealed` whenever the clock ticks.
    @ViewBuilder
    private var clockedContent: some View {
        if clock != nil {
            gridOrEnded
        } else {
            TimelineView(.expiry(expiresAt)) { _ in gridOrEnded }
        }
    }

    @ViewBuilder
    private var gridOrEnded: some View {
        if showsEndedStateWhenExpired && isExpired(expiresAt) {
            VotingEndedView()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Self.sectionSpacing) {
            Text(revealed ? "THE RESULT" : "MAKE YOUR PICK")
                .font(Theme.micro)
                .tracking(1.4)
                .foregroundStyle(Theme.accentDeep)
                .accessibilityAddTraits(.isHeader)

            if let prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            tileLayout
                .overlay {
                    if celebration != nil, !reduceMotion {
                        ConfettiBurst().id(celebration)
                    }
                }
            if let error {
                Text(error).font(Theme.font(.caption)).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if hasVoted {
                resultCard
            }
            actionRow
            if hasVoted {
                reactionsDisclosure
            }
            voteSummary
        }
    }

    private static let sectionSpacing: CGFloat = 12
    private static let tileSpacing: CGFloat = 10

    /// Side by side normally; stacked at accessibility Dynamic Type sizes so
    /// badges and result text keep room to grow.
    @ViewBuilder
    private var tileLayout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Self.tileSpacing) {
                ForEach(photos) { photo in tile(for: photo) }
            }
        } else {
            HStack(spacing: Self.tileSpacing) {
                ForEach(photos) { photo in tile(for: photo) }
            }
        }
    }

    /// Offered only once the result is visible (after voting, or for the
    /// creator), so it never spoils an undecided vote. Only the creator's own
    /// photos are included in the picture; voters share a bars-only card.
    @ViewBuilder
    private var shareAction: some View {
        if showsShare {
            ShareLink(item: shareImage,
                      message: Text(shareMessage),
                      preview: SharePreview("Fit-Check result")) {
                actionLabel("Share", systemImage: "square.and.arrow.up", isPrimary: false)
            }
            .accessibilityLabel("Share result")
            .accessibilityHint("Shares a picture of the result")
        }
    }

    /// One compact row for everything you can do after the result is shown.
    /// Wraps onto a second line at large text sizes instead of truncating.
    @ViewBuilder
    private var actionRow: some View {
        if hasVoted || showsShare {
            FlowLayout(spacing: 8) {
                if hasVoted {
                    Button { commentPhotoId = myVote } label: {
                        actionLabel("Tell them why", systemImage: "text.bubble", isPrimary: true)
                    }
                    .accessibilityHint("Add a comment and what stood out")
                }
                if hasVoted, canVote { changeVoteButton }
                shareAction
            }
        }
    }

    private func actionLabel(_ title: String, systemImage: String, isPrimary: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(Theme.caption)
            .lineLimit(1)
            .foregroundStyle(isPrimary ? Theme.accentDeep : Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: Theme.minTapSize)
            .background(isPrimary ? Theme.accentTint : Theme.muted.opacity(0.65), in: Capsule())
    }

    /// The creator may always export their own result; anyone else only for a
    /// public post, so a group-only or friends-only result never leaves its audience.
    private var canShareResult: Bool { creatorId == voterId || isPublicPost }

    /// Photos are fetched for the picture only from our own storage over https.
    private static func trustedPhotoURL(_ raw: String) -> URL? {
        guard let url = SafeLink.httpsURL(raw), url.host == AppConfig.supabaseURL.host else { return nil }
        return url
    }

    private var shareImage: ResultShareImage {
        ResultShareImage(
            prompt: prompt,
            totalVotes: total,
            rows: photos.map { photo in
                let count = counts[photo.id] ?? 0
                return ResultShareImage.Row(
                    id: photo.id,
                    position: photo.position,
                    percent: total > 0 ? Int((Double(count) / Double(total) * 100).rounded()) : 0,
                    imageURL: Self.trustedPhotoURL(photo.imageUrl),
                    isLeading: count == leadingCount,
                    isMine: myVote == photo.id
                )
            },
            showsPhotos: creatorId == voterId
        )
    }

    private var shareMessage: String {
        if let url = ShareURL.make(fitCheckId: fitCheckId) { return "Vote on CLO·V: \(url.absoluteString)" }
        return "Made with CLO·V"
    }

    private var voteSummary: some View {
        HStack(spacing: 6) {
            if !canVote {
                Text("YOUR FIT-CHECK").font(Theme.micro).tracking(1.1)
                Text("·").accessibilityHidden(true)
            }
            Text(total == 1 ? "1 person has voted" : "\(total) people have voted")
                .font(Theme.microMedium)
        }
        .foregroundStyle(Theme.mutedForeground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func tile(for photo: FitCheckPhoto) -> some View {
        let count = counts[photo.id] ?? 0
        let percent = total > 0 ? Int((Double(count) / Double(total) * 100).rounded()) : 0
        return VoteTile(
            photo: photo,
            percent: percent,
            revealed: revealed,
            isLeading: revealed && total > 0 && count == leadingCount,
            isMine: myVote == photo.id,
            canVote: canVote,
            isDisabled: isVoting,
            onVote: { photoAwaitingConfirmation = photo },
            onZoom: { expandedPhoto = photo },
            hasMyVote: myVote != nil
        )
    }

    private var myPercent: Int {
        guard let myVote, total > 0 else { return 0 }
        return Int((Double(counts[myVote] ?? 0) / Double(total) * 100).rounded())
    }

    /// What the voter's pick means, their streak, and an optional way to say why.
    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(VoteInsight.message(percent: myPercent,
                                     isLeading: (counts[myVote ?? UUID()] ?? 0) == leadingCount,
                                     total: total, optionCount: photos.count))
                .font(Theme.bodyEmphasis)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = streak.summary() {
                Label(summary, systemImage: "flame.fill")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.accentDeep)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softCard(padding: 14)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var changeVoteButton: some View {
        Button { retractVote() } label: {
            actionLabel("Change vote", systemImage: "arrow.uturn.backward", isPrimary: false)
        }
        .disabled(isRetracting || isVoting)
        .accessibilityHint("Cancels your vote so you can pick again while voting is open")
    }

    /// Reactions stay one tap away but out of the way until wanted.
    private var reactionsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsReactions.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("QUICK REACTION").font(Theme.micro).tracking(1.1)
                    Image(systemName: showsReactions ? "chevron.up" : "chevron.down")
                        .font(Theme.micro)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.mutedForeground)
                .frame(minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quick reaction")
            .accessibilityValue(showsReactions ? "expanded" : "collapsed")
            .accessibilityHint("Shows reactions you can send to the poster")
            if showsReactions { quickReactionBar }
        }
    }

    private var quickReactionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(VoteReason.options, id: \.self) { reason in
                        Button { sendQuickReaction(reason) } label: { Text(reason) }
                            .buttonStyle(ChipButtonStyle(
                                isSelected: false,
                                font: Theme.microMedium,
                                unselectedFill: Theme.card,
                                unselectedForeground: Theme.ink,
                                horizontalPadding: 10
                            ))
                            .accessibilityHint("Sends this reaction to the poster")
                            .disabled(isSendingReaction)
                    }
                }
            }
            if let reactionMessage {
                Text(reactionMessage)
                    .font(Theme.micro)
                    .foregroundStyle(Theme.accentDeep)
            }
        }
        .opacity(isSendingReaction ? 0.6 : 1)
    }

    private func sendQuickReaction(_ reason: String) {
        guard !isSendingReaction else { return }
        reactionMessage = nil
        guard let photoId = myVote else {
            setReactionMessage("Vote first, then react")
            return
        }
        isSendingReaction = true
        Haptics.impact(.light) // instant feedback; don't wait for the network
        Task {
            defer { isSendingReaction = false }
            do {
                try await API.saveVoteReason(fitCheckId: fitCheckId, photoId: photoId, tags: [reason], comment: "")
                setReactionMessage("Reaction sent")
            } catch {
                Haptics.error()
                setReactionMessage("Couldn't send reaction")
            }
        }
    }

    private func setReactionMessage(_ message: String) {
        reactionMessage = message
        AccessibilityNotification.Announcement(message).post()
    }

    private func setError(_ message: String) {
        error = message
        AccessibilityNotification.Announcement(message).post()
    }

    private func vote(on photoId: UUID) {
        guard !revealed, !isVoting else { return }
        error = nil
        isVoting = true
        Haptics.impact(.medium)
        myVote = photoId // optimistic
        counts[photoId, default: 0] += 1
        total += 1

        Task {
            defer { isVoting = false }
            do {
                try await API.castVote(fitCheckId: fitCheckId, photoId: photoId, voterId: voterId, creatorId: creatorId, status: status, expiresAt: expiresAt)
                celebrateIfLeading(photoId)
                streak = VoteStreakStore.recordVote(for: voterId)
                AccessibilityNotification.Announcement("Vote recorded, results shown").post()
                appState.contentDidChange()
            } catch APIError.alreadyVoted {
                // The vote exists on the server (another device, or a retry
                // after a lost response); refetch instead of rolling back.
                setError(APIError.alreadyVoted.localizedDescription)
                appState.contentDidChange()
            } catch {
                // The `.sensoryFeedback(.error, trigger: error)` above plays the failure haptic.
                setError(friendlyMessage(for: error, fallback: "Couldn’t record your vote. Please try again."))
                myVote = nil
                counts[photoId, default: 1] -= 1
                total -= 1
            }
        }
    }

    /// Backing the look that is ahead earns a little confetti. A lone first
    /// vote is trivially "leading", so it waits for at least two votes.
    private func celebrateIfLeading(_ photoId: UUID) {
        guard total >= Self.minVotesToCelebrate, (counts[photoId] ?? 0) == leadingCount else { return }
        let id = UUID()
        celebration = id
        Task {
            try? await Task.sleep(for: .seconds(ConfettiBurst.duration))
            if celebration == id { celebration = nil }
        }
    }

    private func retractVote() {
        guard let previous = myVote, canVote, !isRetracting, !isVoting else { return }
        error = nil
        isRetracting = true
        Haptics.impact(.light)
        myVote = nil // optimistic
        counts[previous, default: 1] -= 1
        total -= 1

        Task {
            defer { isRetracting = false }
            do {
                try await API.retractVote(fitCheckId: fitCheckId, voterId: voterId, status: status, expiresAt: expiresAt)
                streak = VoteStreakStore.unrecordVote(for: voterId)
                AccessibilityNotification.Announcement("Vote cancelled. Pick again.").post()
                appState.contentDidChange()
            } catch {
                setError(friendlyMessage(for: error, fallback: "Couldn’t cancel your vote. Please try again."))
                myVote = previous
                counts[previous, default: 0] += 1
                total += 1
            }
        }
    }

    private func syncVotes() {
        guard !isVoting, !isRetracting else { return }
        counts = incomingCounts
        total = incomingTotal
        myVote = incomingVote
    }
}

/// Scale-down-on-press without the default button dimming — keeps
/// photo tiles reading as photos, not chrome.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .motionSafeAnimation(value: configuration.isPressed)
    }
}

/// Thin AsyncImage wrapper with a placeholder background.
struct RemoteImage: View {
    let url: String
    var label: String? = nil

    var body: some View {
        content
            .modifier(RemoteImageAccessibility(label: label))
    }

    @ViewBuilder
    private var content: some View {
        if let imageURL = URL(string: url) {
            CachedImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .loading:
                    ZStack {
                        Theme.muted
                        ProgressView().tint(Theme.mutedForeground)
                    }
                case .failure:
                    ZStack {
                        Theme.muted
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
        } else {
            Theme.muted
        }
    }
}

private struct RemoteImageAccessibility: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isImage)
        } else {
            content.accessibilityHidden(true)
        }
    }
}

extension TimelineSchedule where Self == ExplicitTimelineSchedule<[Date]> {
    /// Ticks once when voting closes (plus a second just after, in case the
    /// first lands a hair early). Stable across re-renders, unlike a
    /// `.periodic(from: .now)` schedule which re-anchors every time.
    static func expiry(_ expiresAt: Date?) -> Self {
        guard let expiresAt else { return .explicit([.distantFuture]) }
        return .explicit([expiresAt, expiresAt.addingTimeInterval(1)])
    }
}
