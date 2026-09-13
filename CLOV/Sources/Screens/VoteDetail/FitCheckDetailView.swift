import SwiftUI

/// Value pushed via `NavigationLink(value:)` to open `FitCheckDetailView`.
/// A dedicated type rather than a bare `UUID` — `GroupsView` already
/// registers `.navigationDestination(for: UUID.self)` for *group* ids on
/// the Groups tab's NavigationStack, and `GroupDetailView` (pushed from
/// there) also shows fit-check cards. A raw `UUID.self` destination for
/// fit-checks would collide with that registration and open the wrong
/// screen — see `GroupDetailView`'s own `FitCheckRoute` registration.
struct FitCheckRoute: Hashable {
    let id: UUID
}

struct FitCheckDetailView: View {
    let fitCheckId: UUID
    @EnvironmentObject private var appState: AppState

    @State private var detail: FitCheckDetailDTO?
    @State private var votes: [VoteRef] = []
    @State private var comments: [CommentDTO] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?

    private var voteCounts: [UUID: Int] {
        Dictionary(grouping: votes, by: \.photoId).mapValues(\.count)
    }
    private var myVote: UUID? {
        votes.first(where: { $0.voterId == appState.userId })?.photoId
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncStateView(isLoading: isLoading, error: error, topPadding: 60,
                               hasLoaded: hasLoaded, retry: { await load() }) {
                    if let detail {
                        let expired = isExpired(detail.expiresAt)

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("FIT CHECK / \((expired ? "ENDED" : detail.status).uppercased())")
                                    .font(.system(.caption2, design: .default).weight(.black))
                                    .tracking(1.4)
                                    .foregroundStyle(Theme.accent)
                                Text("The edit")
                                    .font(.system(size: 40, weight: .black, design: .default))
                            }
                            Spacer()
                            ShareLinkButton(fitCheckId: detail.id)
                        }

                        HStack(spacing: 10) {
                            AvatarView(url: detail.profiles?.avatarUrl, nickname: detail.profiles?.nickname, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((detail.profiles?.nickname ?? "Someone").uppercased())
                                    .font(.system(.subheadline, design: .default).weight(.black))
                                Text("FROM THE CIRCLE")
                                    .font(.system(.caption2, design: .default).weight(.bold))
                                    .tracking(0.8)
                                    .foregroundStyle(Theme.mutedForeground)
                            }
                        }

                        statusStrip(for: detail, expired: expired)

                        if expired {
                            VotingEndedView()
                        } else {
                            if let caption = detail.caption, !caption.isEmpty {
                                Text(caption).font(.subheadline).foregroundStyle(Theme.mutedForeground)
                            }

                            VotingPhotoGridView(
                                fitCheckId: detail.id,
                                creatorId: detail.creatorId,
                                status: detail.status,
                                photos: detail.fitCheckPhotos,
                                voteCounts: voteCounts,
                                totalVotes: votes.count,
                                myVote: myVote,
                                voterId: appState.userId,
                                expiresAt: detail.expiresAt
                            )

                            if detail.status == "archived" {
                                Text("This Fit-Check has ended — voting is closed.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.mutedForeground)
                                    .frame(maxWidth: .infinity)
                            }

                        Text("NOTES FROM THE CIRCLE")
                            .font(.system(.caption2, design: .default).weight(.black))
                            .tracking(1.2)
                            .foregroundStyle(Theme.accent)

                            if comments.isEmpty {
                                Text("No comments yet — vote to leave the first one.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.mutedForeground)
                            } else {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(comments) { comment in
                                        HStack(alignment: .top, spacing: 8) {
                                            AvatarView(url: comment.profiles?.avatarUrl, nickname: comment.profiles?.nickname, size: 28)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(comment.profiles?.nickname ?? "Someone")
                                                    .font(.system(.caption2, design: .default).weight(.black))
                                                Text(comment.body).font(.subheadline)
                                            }
                                        .padding(.horizontal, 12).padding(.vertical, 10)
                                        .background(Theme.card)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Theme.line.opacity(0.2), lineWidth: 1))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appState.contentRevision) { await load() }
        .refreshable { await load() }
    }

    private func statusStrip(for detail: FitCheckDetailDTO, expired: Bool) -> some View {
        HStack {
            Text(expired ? "CLOSED" : "OPEN FOR VOTES")
                .font(.system(.caption2, design: .default).weight(.black))
                .tracking(0.9)
            Spacer()
            if let expiresAt = detail.expiresAt, !expired {
                Text(RelativeDateTimeFormatter().localizedString(for: expiresAt, relativeTo: Date()).uppercased())
                    .font(.system(.caption2, design: .default).weight(.bold))
            } else {
                Text("\(votes.count) VOTES")
                    .font(.system(.caption2, design: .default).weight(.bold))
            }
        }
        .foregroundStyle(Theme.inverseText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.ink)
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let detailTask = API.fetchFitCheckDetail(id: fitCheckId)
            async let votesTask = API.fetchVotes(fitCheckId: fitCheckId)
            async let commentsTask = API.fetchComments(fitCheckId: fitCheckId)
            let loaded = try await (detailTask, votesTask, commentsTask)
            try Task.checkCancellation()
            detail = loaded.0
            votes = loaded.1
            comments = loaded.2
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            self.error = "Couldn’t load this content. Please try again."
        }
    }
}
