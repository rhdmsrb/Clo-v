import SwiftUI

struct FitCheckCardView: View {
    let item: FeedItemDTO
    let voterId: UUID
    let isFollowing: Bool
    let onToggleFollow: ((Bool) -> Void)?

    init(item: FeedItemDTO, voterId: UUID, isFollowing: Bool = false, onToggleFollow: ((Bool) -> Void)? = nil) {
        self.item = item
        self.voterId = voterId
        self.isFollowing = isFollowing
        self.onToggleFollow = onToggleFollow
    }

    private var voteCounts: [UUID: Int] {
        Dictionary(grouping: item.fitCheckVotes, by: \.photoId).mapValues(\.count)
    }
    private var myVote: UUID? {
        item.fitCheckVotes.first(where: { $0.voterId == voterId })?.photoId
    }
    private var commentLabel: String {
        item.fitCheckComments.isEmpty ? "Add a comment" : "\(item.fitCheckComments.count) comment\(item.fitCheckComments.count == 1 ? "" : "s")"
    }
    private var posterName: String { item.profiles?.nickname ?? "Someone" }
    private var showsFollow: Bool { item.creatorId != voterId && onToggleFollow != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            // One timeline per card, ticking once at expiry. The grid stays
            // mounted (and renders the ended state itself) so a comment sheet
            // or zoom cover presented from it survives the card expiring.
            TimelineView(.expiry(item.expiresAt)) { context in
                cardContent(clock: context.date)
            }
        }
        .softCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(posterName)’s Fit-Check")
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                identity(lineLimit: 1)
                Spacer(minLength: 0)
                actions
            }
            VStack(alignment: .leading, spacing: 4) {
                identity(lineLimit: 3)
                HStack(spacing: 10) {
                    actions
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func identity(lineLimit: Int) -> some View {
        HStack(spacing: 10) {
            AvatarView(url: item.profiles?.avatarUrl, nickname: item.profiles?.nickname, size: 36)
            Text(posterName)
                .font(.system(.subheadline, design: .default).weight(.bold))
                .lineLimit(lineLimit)
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if showsFollow, let onToggleFollow {
                followButton(onToggleFollow)
            }
            ShareLinkButton(
                fitCheckId: item.id,
                title: "Share Fit-Check result",
                summary: shareSummary
            )
        }
    }

    private func followButton(_ onToggleFollow: @escaping (Bool) -> Void) -> some View {
        Button { onToggleFollow(!isFollowing) } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(.caption, design: .default).weight(.bold))
                .foregroundStyle(isFollowing ? Theme.mutedForeground : Theme.accent)
                .padding(.horizontal, 8)
                .frame(minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Follow \(posterName)")
        .accessibilityValue(isFollowing ? "Following" : "Not following")
        .accessibilityAddTraits(.isToggle)
    }

    private func cardContent(clock: Date) -> some View {
        let expired = isExpired(item.expiresAt)
        return VStack(alignment: .leading, spacing: 16) {
            VotingPhotoGridView(
                fitCheckId: item.id,
                creatorId: item.creatorId,
                status: "live",
                photos: item.fitCheckPhotos,
                voteCounts: voteCounts,
                totalVotes: item.fitCheckVotes.count,
                myVote: myVote,
                voterId: voterId,
                expiresAt: item.expiresAt,
                prompt: item.votePrompt,
                clock: clock,
                showsEndedStateWhenExpired: true
            )
            if !expired { details }
        }
    }

    @ViewBuilder
    private var details: some View {
        if let caption = item.caption, !caption.isEmpty {
            Text(caption)
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(Theme.ink)
        }

        if let occasion = item.occasion, !occasion.isEmpty {
            Text(occasion)
                .font(.system(.caption, design: .default).weight(.medium))
                .foregroundStyle(Theme.accent)
        }

        NavigationLink(value: FitCheckRoute(id: item.id)) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.fill")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(commentLabel)
                    .font(.system(.caption, design: .default).weight(.semibold))
            }
            .foregroundStyle(Theme.mutedForeground)
            .frame(minHeight: Theme.minTapSize, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    private var shareSummary: String {
        let voteCount = item.fitCheckVotes.count
        if voteCount == 0 { return "Help me choose my outfit on CLO·V." }
        let winner = voteCounts.values.max() ?? 0
        let percentage = Int((Double(winner) / Double(voteCount) * 100).rounded())
        return "My Fit-Check is at \(percentage)% for the leading look (\(voteCount) vote\(voteCount == 1 ? "" : "s"))."
    }
}
