import SwiftUI

/// Network calls the reel vote model makes. Production uses `.live`; tests inject fakes.
struct ReelVoteService {
    var cast: (_ item: FeedItemDTO, _ photoId: UUID, _ voterId: UUID) async throws -> Void
    var retract: (_ item: FeedItemDTO, _ voterId: UUID) async throws -> Void
    var fetchSummary: (_ item: FeedItemDTO, _ voterId: UUID) async throws -> VoteSummary

    static let live = ReelVoteService(
        cast: { item, photoId, voterId in
            try await API.castVote(fitCheckId: item.id, photoId: photoId, voterId: voterId,
                                   creatorId: item.creatorId, status: "live", expiresAt: item.expiresAt)
        },
        retract: { item, voterId in
            try await API.retractVote(fitCheckId: item.id, voterId: voterId,
                                      status: "live", expiresAt: item.expiresAt)
        },
        fetchSummary: { item, voterId in
            try await API.fetchVoteSummary(fitCheckId: item.id, voterId: voterId,
                                           creatorId: item.creatorId, expiresAt: item.expiresAt)
        })
}

/// Vote state for one Fit-Check in the swipe reel: which look is on screen,
/// the running tally, and casting a vote with an optimistic update.
@MainActor
final class ReelVoteModel: ObservableObject {
    private let item: FeedItemDTO
    private let voterId: UUID
    private let service: ReelVoteService
    /// False for a post whose status is not `live` (e.g. archived) even if its timer
    /// has not run out; such a post is closed to voting and shows its results.
    private let isLive: Bool
    private var pendingTask: Task<Void, Never>?

    let photos: [FitCheckPhoto]
    @Published private(set) var lookIndex: Int
    @Published private(set) var counts: [UUID: Int]
    @Published private(set) var total: Int
    @Published private(set) var myVote: UUID?
    @Published private(set) var isVoting = false
    @Published private(set) var isRetracting = false
    @Published private(set) var streak: VoteStreak
    @Published var error: String?
    @Published private(set) var summaryLoaded: Bool
    @Published private(set) var summaryLoadFailed = false

    /// `initialSummary` is a summary the caller already fetched from the server; it
    /// replaces any seeds supplied by an in-memory caller.
    init(item: FeedItemDTO, voterId: UUID, initialLook: Int? = nil, isLive: Bool = true,
         initialSummary: VoteSummary? = nil, service: ReelVoteService = .live) {
        self.item = item
        self.voterId = voterId
        self.isLive = isLive
        self.service = service
        photos = item.fitCheckPhotos.sorted { $0.position < $1.position }
        lookIndex = Self.clampedLook(initialLook, count: photos.count)
        // Feed queries omit vote rows. In-memory seeds are used only until the
        // authoritative summary arrives; voting waits for that summary.
        counts = Dictionary(grouping: item.fitCheckVotes, by: \.photoId).mapValues(\.count)
        total = item.voteCount ?? item.fitCheckVotes.count
        myVote = item.fitCheckVotes.first { $0.voterId == voterId }?.photoId
        summaryLoaded = initialSummary != nil
        streak = VoteStreakStore.load(for: voterId)
        if let initialSummary { apply(initialSummary) }
    }

    /// An out-of-range or missing index opens on the first look.
    nonisolated static func clampedLook(_ index: Int?, count: Int) -> Int {
        guard let index, (0..<count).contains(index) else { return 0 }
        return index
    }

    var currentPhoto: FitCheckPhoto? { photos.indices.contains(lookIndex) ? photos[lookIndex] : photos.first }
    /// False while a vote or an undo is in flight so the two never overlap.
    var canVote: Bool { isVotingOpen && summaryLoaded && myVote == nil && !isWriteInFlight }
    /// A cast vote can be taken back while the post is live.
    var canRetract: Bool { isVotingOpen && summaryLoaded && myVote != nil && !isWriteInFlight }
    /// The post is live and this viewer is not its creator, whether or not they have voted yet.
    var isVotingOpen: Bool { !isCreator && !isEnded }
    /// First-time voters get a hint about the hold gesture.
    var isFirstTimeVoter: Bool { streak.lastVoteDay == nil }
    var isCreator: Bool { item.creatorId == voterId }
    var isEnded: Bool { isExpired(item.expiresAt) || !isLive }
    /// Vote totals and the per-photo split stay blurred until this is true.
    var isResultsRevealed: Bool {
        BlurReveal.isRevealed(hasVoted: myVote != nil, isCreator: isCreator, ended: isEnded)
    }

    func percent(for photoId: UUID) -> Int {
        total > 0 ? Int((Double(counts[photoId] ?? 0) / Double(total) * 100).rounded()) : 0
    }

    var insight: String? {
        guard let myVote else { return nil }
        let leading = counts.values.max() ?? 0
        return VoteInsight.message(percent: percent(for: myVote), isLeading: (counts[myVote] ?? 0) == leading,
                                   total: total, optionCount: photos.count)
    }

    /// Browses to a photo, ignoring out-of-range indexes.
    func setLook(_ index: Int) {
        guard photos.indices.contains(index), index != lookIndex else { return }
        lookIndex = index
    }

    func showLook(step: Int) {
        lookIndex = SwipeVoteGesture.index(after: lookIndex, count: photos.count, step: step)
    }

    /// Suspends until the in-flight vote or undo (if any) finishes.
    func waitUntilIdle() async {
        await pendingTask?.value
    }

    /// Votes for the look on screen. Returns whether a vote was started.
    @discardableResult
    func voteForCurrentLook(onRecorded: @escaping () -> Void) -> Bool {
        guard let photo = currentPhoto else { return false }
        return vote(for: photo.id, onRecorded: onRecorded)
    }

    /// Votes for a specific photo (a tapped tile). Returns whether a vote was started.
    @discardableResult
    func vote(for photoId: UUID, onRecorded: @escaping () -> Void) -> Bool {
        guard canVote, photos.contains(where: { $0.id == photoId }) else { return false }
        let before = (counts: counts, total: total)
        error = nil
        isVoting = true
        myVote = photoId // optimistic
        counts = counts.merging([photoId: 1], uniquingKeysWith: +)
        total = before.total + 1

        pendingTask = Task {
            var didRecordVote = false
            defer {
                isVoting = false
                if didRecordVote { onRecorded() }
            }
            do {
                try await service.cast(item, photoId, voterId)
                Haptics.success()
                streak = VoteStreakStore.recordVote(for: voterId)
                await syncAfterWrite(fallbackVote: photoId)
                didRecordVote = true
            } catch APIError.alreadyVoted {
                // The server already had a vote: drop our optimistic increment, then resync.
                error = APIError.alreadyVoted.localizedDescription
                counts = before.counts
                total = before.total
                await resyncFromServer(fallbackVote: photoId)
                didRecordVote = true
            } catch {
                // A timeout can lose the response after the vote landed; trust the server.
                if let summary = await serverSummary(), summary.myVote == photoId {
                    Haptics.success()
                    streak = VoteStreakStore.recordVote(for: voterId)
                    apply(summary, fallbackVote: photoId)
                    didRecordVote = true
                    return
                }
                Haptics.error()
                self.error = friendlyMessage(for: error, fallback: "Couldn’t record your vote. Please try again.")
                myVote = nil
                counts = before.counts
                total = before.total
            }
        }
        return true
    }

    /// Takes back the vote so the voter can pick again. Optimistic, rolled back on failure.
    func retractVote(onRecorded: @escaping () -> Void) {
        guard canRetract, let previous = myVote else { return }
        let before = (counts: counts, total: total)
        error = nil
        isRetracting = true
        myVote = nil
        counts = counts.merging([previous: -1], uniquingKeysWith: +).filter { $0.value > 0 }
        total = max(0, before.total - 1)

        pendingTask = Task {
            var didRetractVote = false
            defer {
                isRetracting = false
                if didRetractVote { onRecorded() }
            }
            do {
                try await service.retract(item, voterId)
                streak = VoteStreakStore.unrecordVote(for: voterId)
                await syncAfterWrite(fallbackVote: nil)
                didRetractVote = true
            } catch {
                // The undo may have landed even though its response was lost.
                if let summary = await serverSummary(), summary.myVote == nil {
                    streak = VoteStreakStore.unrecordVote(for: voterId)
                    apply(summary, fallbackVote: nil)
                    didRetractVote = true
                    return
                }
                Haptics.error()
                self.error = friendlyMessage(for: error, fallback: "Couldn’t undo your vote. Please try again.")
                myVote = previous
                counts = before.counts
                total = before.total
            }
        }
    }

    /// Call from the screen's `.task`: loads the server's counts and the viewer's own vote.
    func loadSummary() async {
        await refreshSummary()
    }

    /// Replaces the local tally with the server's. Skipped while a vote or undo is in
    /// flight (its own resync follows). Never throws.
    func refreshSummary() async {
        guard !isWriteInFlight else { return }
        do {
            let summary = try await service.fetchSummary(item, voterId)
            guard !isWriteInFlight else { return }
            // Idle, so the server is the truth: a summary with no vote clears a stale local one.
            apply(summary)
            summaryLoaded = true
            summaryLoadFailed = false
        } catch {
            summaryLoadFailed = true
            Log.app.error("ReelVoteModel summary refresh failed: \(error.localizedDescription)")
        }
    }

    /// Takes a summary the parent screen just loaded from the server as the truth, so a
    /// screen-level reload and this model never disagree. Ignored while a write is in
    /// flight (that write resyncs itself). Unlike `refreshSummary`, a summary with no
    /// vote clears a stale local one.
    func adopt(_ summary: VoteSummary) {
        guard !isWriteInFlight else { return }
        apply(summary)
        summaryLoaded = true
        summaryLoadFailed = false
    }

    private var isWriteInFlight: Bool { isVoting || isRetracting }

    private func apply(_ summary: VoteSummary) {
        apply(summary, fallbackVote: summary.myVote)
    }

    /// Applies a server summary. Counts and totals are taken only when it is revealed.
    private func apply(_ summary: VoteSummary, fallbackVote: UUID?) {
        myVote = summary.myVote ?? fallbackVote
        guard summary.isRevealed else { return }
        counts = summary.counts
        total = summary.total
    }

    /// The server's current summary, or nil when it can't be read.
    private func serverSummary() async -> VoteSummary? {
        try? await service.fetchSummary(item, voterId)
    }

    /// After a successful write, resyncs truth from the server; keeps the optimistic
    /// numbers if the fetch fails.
    private func syncAfterWrite(fallbackVote: UUID?) async {
        do {
            apply(try await service.fetchSummary(item, voterId), fallbackVote: fallbackVote)
        } catch {
            Log.app.error("ReelVoteModel post-write resync failed: \(error.localizedDescription)")
        }
    }

    /// Reloads the tally from the server. If that fails, keeps the pre-vote tally and marks
    /// the voter as having voted (the server rejected a second vote).
    private func resyncFromServer(fallbackVote: UUID) async {
        do {
            apply(try await service.fetchSummary(item, voterId), fallbackVote: fallbackVote)
        } catch {
            Log.app.error("ReelVoteModel already-voted resync failed: \(error.localizedDescription)")
            myVote = fallbackVote
        }
    }
}
