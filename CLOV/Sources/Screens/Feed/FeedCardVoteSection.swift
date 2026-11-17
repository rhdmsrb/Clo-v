import SwiftUI

/// Voting on the feed post itself: one button per look until the viewer votes,
/// then each look's share of the votes with an Undo. It reuses `ReelVoteModel`, so
/// the optimistic update, rollback and server resync match the vote screen.
struct FeedCardVoteSection: View {
    let item: FeedItemDTO
    let viewerId: UUID
    /// Index (in position order) of the photo the card's carousel is showing; its button is emphasised.
    let highlightedIndex: Int
    /// Called with the viewer's vote (`nil` after an undo) once the server has confirmed it.
    let onVoteChange: (UUID?) -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: ReelVoteModel

    private static let barHeight: CGFloat = 10
    private static let labelWidth: CGFloat = 60
    private static let percentWidth: CGFloat = 46

    init(item: FeedItemDTO, viewerId: UUID, highlightedIndex: Int,
         onVoteChange: @escaping (UUID?) -> Void, service: ReelVoteService = .live) {
        self.item = item
        self.viewerId = viewerId
        self.highlightedIndex = highlightedIndex
        self.onVoteChange = onVoteChange
        _model = StateObject(wrappedValue: ReelVoteModel(item: item, voterId: viewerId, service: service))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isResultsRevealed {
                results
            } else {
                voteButtons
            }
            if let error = model.error {
                Text(error)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("feed-vote-error")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .animation(Theme.animation(Theme.settle, reduceMotion: reduceMotion), value: model.myVote)
        // Totals are only worth a request when they are shown: already voted, ended, or the creator.
        .task { if model.myVote != nil || model.isEnded || model.isCreator { await model.loadSummary() } }
        // A vote made elsewhere (the vote screen) reaches this card through the reloaded item.
        .onChange(of: item.ownVote(voterId: viewerId)) { _, seeded in
            guard let seeded, seeded != model.myVote else { return }
            Task { await model.refreshSummary() }
        }
    }

    // MARK: Before voting

    private var voteButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttonViews }
            VStack(spacing: 8) { buttonViews }
        }
        .disabled(!model.canVote)
        .accessibilityElement(children: .contain)
    }

    private var buttonViews: some View {
        ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
            Button { vote(for: photo) } label: {
                Text(PostCardContent.voteButtonTitle(position: photo.position))
                    .font(Theme.font(.subheadline, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(index == highlightedIndex ? Theme.accentForeground : Theme.accentDeep)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTapSize)
                    .background(index == highlightedIndex ? Theme.accent : Theme.accentTint, in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).stroke(Theme.accentDeep, lineWidth: 1))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PostCardContent.voteButtonAccessibilityLabel(position: photo.position))
            .accessibilityIdentifier("feed-vote-button-\(photo.position)")
        }
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
                .frame(width: Self.labelWidth, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.accentTint)
                    Capsule()
                        .fill(isMine ? Theme.accentDeep : Theme.accent)
                        .frame(width: proxy.size.width * CGFloat(percent) / 100)
                }
            }
            .frame(height: Self.barHeight)
            HStack(spacing: 4) {
                if isMine { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accentDeep) }
                Text("\(percent)%").font(Theme.caption).monospacedDigit().foregroundStyle(Theme.ink)
            }
            .frame(width: Self.percentWidth, alignment: .trailing)
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

    private func vote(for photo: FitCheckPhoto) {
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
