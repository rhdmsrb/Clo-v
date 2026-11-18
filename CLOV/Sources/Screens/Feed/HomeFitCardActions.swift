import SwiftUI

/// The line under the hero photo: author on the left; Send and the "…" menu (share,
/// report, block, follow) on the right. Like and Comment sit on the photo itself.
struct HomeFitCardActions: View {
    let item: FeedItemDTO
    let title: String
    let posterName: String
    let viewerId: UUID
    let isFollowing: Bool
    let onToggleFollow: ((Bool) -> Void)?

    var body: some View {
        HStack(spacing: Spacing.s) {
            AvatarView(url: item.profiles?.avatarUrl, nickname: item.profiles?.nickname, size: 28)
            Text(posterName)
                .font(Theme.font(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            ShareLink(item: PostCardContent.shareText(title: title, url: ShareURL.make(fitCheckId: item.id)),
                      subject: Text(title)) {
                Image(systemName: "paperplane")
                    .foregroundStyle(Theme.ink)
                    .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(InstantPressStyle())
            .accessibilityLabel("Send")
            .accessibilityIdentifier("feed-send-button")
            FitCheckMoreMenu(fitCheckId: item.id, creatorId: item.creatorId, posterName: posterName,
                             viewerId: viewerId, isFollowing: isFollowing, onToggleFollow: onToggleFollow)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}
