import SwiftUI

struct FitCheckCardView: View {
    let item: FeedItemDTO
    let voterId: UUID

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AvatarView(url: item.profiles?.avatarUrl, nickname: item.profiles?.nickname, size: 36)
                Text(item.profiles?.nickname ?? "Someone")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                Spacer()
                ShareLinkButton(fitCheckId: item.id)
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
                    expiresAt: item.expiresAt
                )

                if let caption = item.caption, !caption.isEmpty {
                    Text(caption).font(.system(.subheadline, design: .rounded))
                }

                NavigationLink(value: FitCheckRoute(id: item.id)) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 11))
                        Text(commentLabel)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                    }
                    .foregroundStyle(Theme.mutedForeground)
                }
            }
        }
        .softCard()
    }
}
