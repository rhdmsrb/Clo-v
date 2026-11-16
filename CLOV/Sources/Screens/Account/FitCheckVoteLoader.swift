@preconcurrency import SwiftUI

/// Opens the hold-to-vote screen for a post known only by id (profile tiles,
/// `clov://vote/<id>` links). Fetches the post, shows `FitCheckReelView` when
/// it is live and unexpired, and otherwise (ended, archived, blocked, not
/// found, or a load failure) falls back to `FitCheckDetailView`, which owns
/// the "Voting has ended" and error states.
struct FitCheckVoteLoader: View {
    let fitCheckId: UUID
    @EnvironmentObject private var appState: AppState

    private enum Phase {
        case loading
        case reel(FeedItemDTO)
        case fallback
    }

    @State private var phase: Phase = .loading
    @State private var isFollowingCreator = false

    var body: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .task(id: fitCheckId) { await load() }
        case .reel(let item):
            FitCheckReelView(
                item: item,
                voterId: appState.userId,
                isFollowing: isFollowingCreator,
                onToggleFollow: { setFollowing($0, creatorId: item.creatorId) }
            )
        case .fallback:
            FitCheckDetailView(fitCheckId: fitCheckId)
        }
    }

    private func load() async {
        guard let detail = try? await API.fetchFitCheckDetail(id: fitCheckId),
              detail.status == "live", !isExpired(detail.expiresAt) else {
            phase = .fallback
            return
        }
        // Without the viewer's own vote the reel would show a voter as "hasn't voted",
        // so a failed fetch falls back to the detail screen instead.
        let summary: VoteSummary
        do {
            summary = try await API.fetchVoteSummary(fitCheckId: fitCheckId, voterId: appState.userId,
                                                     creatorId: detail.creatorId, expiresAt: detail.expiresAt)
        } catch {
            Log.app.error("FitCheckVoteLoader votes fetch failed: \(error.localizedDescription)")
            phase = .fallback
            return
        }
        let following = (try? await API.fetchFollowingIDs(userId: appState.userId)) ?? []
        isFollowingCreator = following.contains(detail.creatorId)
        phase = .reel(FeedItemDTO(
            id: detail.id,
            creatorId: detail.creatorId,
            caption: detail.caption,
            occasion: detail.occasion,
            audience: detail.audience,
            votePrompt: detail.votePrompt,
            createdAt: Date(),
            expiresAt: detail.expiresAt,
            fitCheckPhotos: detail.fitCheckPhotos,
            fitCheckVotes: summary.myVote.map { [VoteRef(photoId: $0, voterId: appState.userId)] } ?? [],
            fitCheckComments: [],
            profiles: detail.profiles,
            isPublic: detail.isPublic,
            voteCount: summary.isRevealed ? summary.total : nil
        ))
    }

    private func setFollowing(_ follow: Bool, creatorId: UUID) {
        isFollowingCreator = follow
        Task {
            do {
                try await API.setFollowing(follow, followerId: appState.userId, followingId: creatorId)
            } catch {
                isFollowingCreator = !follow
            }
        }
    }
}
