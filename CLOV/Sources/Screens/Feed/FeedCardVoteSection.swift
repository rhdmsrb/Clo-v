import SwiftUI

/// What the card's photos need to take a vote: whether a press may vote, and how to cast it.
struct PhotoVoteAction {
    let isEnabled: Bool
    let cast: () -> Void
}

private enum VoteSectionMetrics {
    static let barHeight: CGFloat = 10
    static let labelWidth: CGFloat = 60
    static let percentWidth: CGFloat = 46
    static let photoToVoteSpacing: CGFloat = 10
}

/// Voting on the feed post itself: press and hold the photo you like. Until the viewer votes a hint
/// says so; afterwards each look's share of the votes shows with an Undo. It reuses `ReelVoteModel`,
/// so the optimistic update, rollback and server resync match the vote screen. The view lays out the
/// card's photos (built by the caller, which attaches the press gesture) above the hint or results.
struct FeedCardVoteSection<Photos: View>: View {
    let item: FeedItemDTO
    let viewerId: UUID
    /// Index (in position order) of the photo the card's carousel is showing; a press votes for it.
    let photoIndex: Int
    /// Side inset for the hint and results; the photos themselves span the full width.
    let textInset: CGFloat
    /// Called with the viewer's vote (`nil` after an undo) once the server has confirmed it.
    let onVoteChange: (UUID?) -> Void
    @ViewBuilder let photos: (PhotoVoteAction) -> Photos

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: ReelVoteModel


    init(item: FeedItemDTO, viewerId: UUID, photoIndex: Int, textInset: CGFloat,
         onVoteChange: @escaping (UUID?) -> Void, service: ReelVoteService = .live,
         @ViewBuilder photos: @escaping (PhotoVoteAction) -> Photos) {
        self.item = item
        self.viewerId = viewerId
        self.photoIndex = photoIndex
        self.textInset = textInset
        self.onVoteChange = onVoteChange
        self.photos = photos
        _model = StateObject(wrappedValue: ReelVoteModel(item: item, voterId: viewerId, service: service))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VoteSectionMetrics.photoToVoteSpacing) {
            photos(PhotoVoteAction(isEnabled: model.canVote, cast: castVoteForShownPhoto))
            status.padding(.horizontal, textInset)
        }
        .animation(Theme.animation(Theme.settle, reduceMotion: reduceMotion), value: model.myVote)
        // The feed query carries no vote rows (other viewers' votes stay private), so the viewer's
        // own vote, and the totals when they may see them, come from the summary request.
        .task { await model.loadSummary() }
        // A vote made elsewhere (the vote screen) reaches this card through the reloaded item.
        .onChange(of: item.ownVote(voterId: viewerId)) { _, seeded in
            guard let seeded, seeded != model.myVote else { return }
            Task { await model.refreshSummary() }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isResultsRevealed {
                results
            } else {
                voteHint
            }
            if let error = model.error {
                Text(error)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("feed-vote-error")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    // MARK: Before voting

    private var voteHint: some View {
        Label("Press and hold a photo to vote for it", systemImage: "hand.tap")
            .font(Theme.caption)
            .foregroundStyle(model.canVote ? Theme.accentDeep : Theme.mutedForeground)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapSize / 2, alignment: .leading)
            .accessibilityIdentifier("feed-vote-hint")
    }

    // MARK: After voting, or when results are open to the viewer

    private var results: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.photos) { photo in resultRow(photo) }
            HStack {
                Text(footerText)
                    .font(Theme.micro)
                    .foregroundStyle(Theme.mutedForeground)
                Spacer(minLength: 0)
                if model.canRetract { undoButton }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed-vote-results")
    }

    private func resultRow(_ photo: FitCheckPhoto) -> some View {
        let percent = model.percent(for: photo.id)
        let isMine = model.myVote == photo.id
        let title = PostCardContent.voteButtonTitle(position: photo.position)
        return HStack(spacing: 8) {
            Text(title)
                .font(Theme.caption)
                .foregroundStyle(Theme.ink)
                .frame(width: VoteSectionMetrics.labelWidth, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.accentTint)
                    Capsule()
                        .fill(isMine ? Theme.accentDeep : Theme.accent)
                        .frame(width: proxy.size.width * CGFloat(percent) / 100)
                }
            }
            .frame(height: VoteSectionMetrics.barHeight)
            HStack(spacing: 4) {
                if isMine { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accentDeep) }
                Text("\(percent)%").font(Theme.caption).monospacedDigit().foregroundStyle(Theme.ink)
            }
            .frame(width: VoteSectionMetrics.percentWidth, alignment: .trailing)
        }
        .frame(minHeight: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(percent) percent\(isMine ? ", your vote" : "")")
    }

    private var undoButton: some View {
        Button(action: undo) {
            Text("Undo")
                .font(Theme.font(.footnote, weight: .semibold))
                .foregroundStyle(Theme.accentDeep)
                .padding(.horizontal, 12)
                .frame(minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Undo vote")
        .accessibilityIdentifier("feed-vote-undo")
    }

    private var footerText: String {
        let votes = model.total == 1 ? "1 vote" : "\(model.total) votes"
        if model.isEnded { return "Voting ended · \(votes)" }
        if model.isCreator { return "Your Fit-Check · \(votes)" }
        return votes
    }

    // MARK: Actions

    private func castVoteForShownPhoto() {
        guard let photo = PostCardContent.photo(at: photoIndex, in: model.photos) else { return }
        let started = model.vote(for: photo.id) { recorded() }
        AccessibilityNotification.Announcement(started ? "Vote recorded, results shown" : "Vote not recorded").post()
    }

    private func undo() {
        guard model.canRetract else { return }
        Haptics.impact(.light)
        model.retractVote { recorded() }
        AccessibilityNotification.Announcement("Vote undone. Pick again.").post()
    }

    /// Runs once the server confirmed a vote or an undo: tell the feed, and refresh other screens.
    private func recorded() {
        onVoteChange(model.myVote)
        appState.contentDidChange()
    }
}
