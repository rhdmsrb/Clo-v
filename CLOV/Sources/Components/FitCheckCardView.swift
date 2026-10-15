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
    private var expired: Bool { isExpired(item.expiresAt) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                AvatarView(url: item.profiles?.avatarUrl, nickname: item.profiles?.nickname, size: 36)
                Text(item.profiles?.nickname ?? "Someone")
                    .font(.system(.subheadline, design: .default).weight(.bold))
                Spacer()
                if item.creatorId != voterId, let onToggleFollow {
                    Button(isFollowing ? "Following" : "Follow") {
                        onToggleFollow(!isFollowing)
                    }
                    .font(.system(.caption, design: .default).weight(.bold))
                    .foregroundStyle(isFollowing ? Theme.mutedForeground : Theme.accent)
                    .accessibilityLabel(isFollowing ? "Unfollow \(item.profiles?.nickname ?? "user")" : "Follow \(item.profiles?.nickname ?? "user")")
                }
                ShareLinkButton(
                    fitCheckId: item.id,
                    title: "Share Fit-Check result",
                    summary: shareSummary
                )
            }

            if expired {
                VotingEndedView()
            } else {
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
                    prompt: item.votePrompt
                )

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
                            .font(.system(size: 11))
                        Text(commentLabel)
                            .font(.system(.caption, design: .default).weight(.semibold))
                    }
                    .foregroundStyle(Theme.mutedForeground)
                }
            }
        }
        .softCard()
    }

    private var shareSummary: String {
        let voteCount = item.fitCheckVotes.count
        if voteCount == 0 { return "Help me choose my outfit on CLO·V." }
        let winner = voteCounts.values.max() ?? 0
        let percentage = Int((Double(winner) / Double(voteCount) * 100).rounded())
        return "My Fit-Check is at \(percentage)% for the leading look (\(voteCount) vote\(voteCount == 1 ? "" : "s"))."
    }
}
