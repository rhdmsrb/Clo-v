import SwiftUI

/// Like / Comment / Send on the left, the "…" menu (share, report, block, follow)
/// on the right. Identifiers match the previous feed card so UI tests keep working.
struct HomeFitCardActions: View {
    let item: FeedItemDTO
    let title: String
    let posterName: String
    let viewerId: UUID
    let isLiked: Bool
    let isFollowing: Bool
    let onToggleFollow: ((Bool) -> Void)?
    let onLike: (Bool) async throws -> Void
    let onComment: () -> Void

    private var commentCount: Int { item.fitCheckComments.count }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            LikeButton(isLiked: isLiked, count: PostCardContent.displayLikeCount(item.likeCount), title: "Like",
                       accessibilityIdentifier: "feed-like-button", perform: onLike)
            Button(action: onComment) {
                label("Comment", systemImage: "bubble.left", count: PostCardContent.displayLikeCount(commentCount))
            }
            .buttonStyle(InstantPressStyle())
            .accessibilityLabel("Comments")
            .accessibilityValue(commentCount > 0 ? "\(commentCount)" : "")
            .accessibilityIdentifier("feed-comment-button")
            ShareLink(item: PostCardContent.shareText(title: title, url: ShareURL.make(fitCheckId: item.id)),
                      subject: Text(title)) {
                label("Send", systemImage: "paperplane")
            }
            .buttonStyle(InstantPressStyle())
            .accessibilityLabel("Send")
            .accessibilityIdentifier("feed-send-button")
            Spacer(minLength: 0)
            FitCheckMoreMenu(fitCheckId: item.id, creatorId: item.creatorId, posterName: posterName,
                             viewerId: viewerId, isFollowing: isFollowing, onToggleFollow: onToggleFollow)
        }
        .font(.system(.body))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func label(_ text: String, systemImage: String, count: Int? = nil) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: systemImage)
            Text(text).font(Theme.font(.footnote, weight: .semibold)).lineLimit(1)
            if let count {
                Text("\(count)").font(Theme.font(.footnote, weight: .semibold)).monospacedDigit()
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, Spacing.xs + 2)
        .frame(minHeight: Theme.minTapSize)
        .contentShape(Rectangle())
    }
}
