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
        VStack(alignment: .leading, spacing: 14) {
            header
            // One timeline per card, ticking once at expiry. The grid stays
            // mounted (and renders the ended state itself) so a comment sheet
            // or zoom cover presented from it survives the card expiring.
            TimelineView(.expiry(item.expiresAt)) { context in
                cardContent(clock: context.date)
            }
        }
        .elevatedCard(radius: Theme.cardRadius, padding: 14)
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
            AvatarView(url: item.profiles?.avatarUrl, nickname: item.profiles?.nickname, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(posterName)
                    .font(Theme.headline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(lineLimit)
                occasionCapsule
            }
        }
    }

    @ViewBuilder
    private var occasionCapsule: some View {
        if let occasion = item.occasion, !occasion.isEmpty {
            Text(occasion)
                .font(Theme.micro)
                .foregroundStyle(Theme.accentDeep)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Theme.accentTint, in: Capsule(style: .continuous))
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
            Label(isFollowing ? "Following" : "Follow", systemImage: isFollowing ? "checkmark" : "plus")
                .font(Theme.caption)
                .foregroundStyle(isFollowing ? Theme.accentDeep : Theme.ink)
                .lineLimit(1)
                .contentTransition(.symbolEffect(.replace))
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(isFollowing ? Theme.accentTint : Color.clear, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous)
                    .stroke(isFollowing ? Theme.accentDeep : Theme.controlBorder, lineWidth: 1))
                .frame(minHeight: Theme.minTapSize)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .motionSafeAnimation(Theme.snap, value: isFollowing)
        .sensoryFeedback(.selection, trigger: isFollowing)
        .accessibilityLabel("Follow \(posterName)")
        .accessibilityValue(isFollowing ? "Following" : "Not following")
        .accessibilityAddTraits(.isToggle)
    }

    private func cardContent(clock: Date) -> some View {
        let expired = isExpired(item.expiresAt)
        return VStack(alignment: .leading, spacing: 12) {
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
                showsEndedStateWhenExpired: true,
                isPublicPost: item.isPublic == true
            )
            if !expired { details }
        }
    }

    @ViewBuilder
    private var details: some View {
        if let caption = item.caption, !caption.isEmpty {
            Text(caption)
                .font(Theme.font(.subheadline))
                .foregroundStyle(Theme.ink)
        }

        NavigationLink(value: FitCheckRoute(id: item.id)) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.fill")
                    .font(.caption)
                    .accessibilityHidden(true)
                Text(commentLabel)
                    .font(Theme.label)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.mutedForeground)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapSize, alignment: .leading)
            .background(Theme.muted, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
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
