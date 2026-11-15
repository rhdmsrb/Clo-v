import SwiftUI

/// Vote state for one Fit-Check in the swipe reel: which look is on screen,
/// the running tally, and casting a vote with an optimistic update.
@MainActor
final class ReelVoteModel: ObservableObject {
    private let item: FeedItemDTO
    private let voterId: UUID

    let photos: [FitCheckPhoto]
    @Published private(set) var lookIndex = 0
    @Published private(set) var counts: [UUID: Int]
    @Published private(set) var total: Int
    @Published private(set) var myVote: UUID?
    @Published private(set) var isVoting = false
    @Published private(set) var isRetracting = false
    @Published private(set) var streak: VoteStreak
    @Published var error: String?

    init(item: FeedItemDTO, voterId: UUID) {
        self.item = item
        self.voterId = voterId
        photos = item.fitCheckPhotos.sorted { $0.position < $1.position }
        counts = Dictionary(grouping: item.fitCheckVotes, by: \.photoId).mapValues(\.count)
        total = item.fitCheckVotes.count
        myVote = item.fitCheckVotes.first { $0.voterId == voterId }?.photoId
        streak = VoteStreakStore.load(for: voterId)
    }

    var currentPhoto: FitCheckPhoto? { photos.indices.contains(lookIndex) ? photos[lookIndex] : photos.first }
    var canVote: Bool { item.creatorId != voterId && myVote == nil && !isExpired(item.expiresAt) }
    /// A cast vote can be taken back while the post is live.
    var canRetract: Bool {
        item.creatorId != voterId && myVote != nil
            && !isExpired(item.expiresAt) && !isVoting && !isRetracting
    }
    /// First-time voters get a hint about the swipe.
    var isFirstTimeVoter: Bool { streak.lastVoteDay == nil }

    func percent(for photoId: UUID) -> Int {
        total > 0 ? Int((Double(counts[photoId] ?? 0) / Double(total) * 100).rounded()) : 0
    }

    var insight: String? {
        guard let myVote else { return nil }
        let leading = counts.values.max() ?? 0
        return VoteInsight.message(percent: percent(for: myVote), isLeading: (counts[myVote] ?? 0) == leading,
                                   total: total, optionCount: photos.count)
    }

    func showLook(step: Int) {
        lookIndex = SwipeVoteGesture.index(after: lookIndex, count: photos.count, step: step)
    }

    /// Votes for the look on screen. Returns whether a vote was started.
    @discardableResult
    func voteForCurrentLook(onRecorded: @escaping () -> Void) -> Bool {
        guard canVote, !isVoting, let photo = currentPhoto else { return false }
        error = nil
        isVoting = true
        myVote = photo.id // optimistic
        counts[photo.id, default: 0] += 1
        total += 1

        Task {
            defer { isVoting = false }
            do {
                try await API.castVote(fitCheckId: item.id, photoId: photo.id, voterId: voterId,
                                       creatorId: item.creatorId, status: "live", expiresAt: item.expiresAt)
                Haptics.success()
                streak = VoteStreakStore.recordVote(for: voterId)
                onRecorded()
            } catch APIError.alreadyVoted {
                // The vote exists server-side (another device, or a retry); keep it.
                error = APIError.alreadyVoted.localizedDescription
                onRecorded()
            } catch {
                Haptics.error()
                self.error = friendlyMessage(for: error, fallback: "Couldn’t record your vote. Please try again.")
                myVote = nil
                counts[photo.id, default: 1] -= 1
                total -= 1
            }
        }
        return true
    }

    /// Takes back the vote so the voter can pick again. Optimistic, rolled back on failure.
    func retractVote(onRecorded: @escaping () -> Void) {
        guard canRetract, let previous = myVote else { return }
        error = nil
        isRetracting = true
        myVote = nil
        counts[previous, default: 1] -= 1
        total -= 1

        Task {
            defer { isRetracting = false }
            do {
                try await API.retractVote(fitCheckId: item.id, voterId: voterId,
                                          status: "live", expiresAt: item.expiresAt)
                streak = VoteStreakStore.unrecordVote(for: voterId)
                onRecorded()
            } catch {
                Haptics.error()
                self.error = friendlyMessage(for: error, fallback: "Couldn’t undo your vote. Please try again.")
                myVote = previous
                counts[previous, default: 0] += 1
                total += 1
            }
        }
    }
}
