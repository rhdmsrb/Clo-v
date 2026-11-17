import Foundation
import Supabase

/// Which server path a viewer's vote summary must use.
enum VoteSummaryPlan: Equatable {
    case hidden
    case live
    case closed

    static func decide(isEnded: Bool, isCreator: Bool, hasVoted: Bool) -> VoteSummaryPlan {
        if isEnded { return .closed }
        return (isCreator || hasVoted) ? .live : .hidden
    }
}

/// Vote totals that respect the restricted `fit_check_votes` SELECT policy.
extension API {

    private struct WornLook: Codable {
        let fitCheckId: UUID
        let photoId: UUID
    }

    @MainActor static func wornLook(for id: UUID) async throws -> UUID? {
#if DEBUG
        if SampleData.isActive { return sampleWornLooks[id] }
#endif
        let rows: [WornLook] = try await client.from("fit_check_worn_looks")
            .select().eq("fit_check_id", value: id).execute().value
        return rows.first?.photoId
    }

#if DEBUG
    @MainActor private static var sampleWornLooks: [UUID: UUID] = [:]
#endif

    @MainActor static func chooseWornLook(_ photo: UUID, for id: UUID) async throws {
#if DEBUG
        if SampleData.isActive { sampleWornLooks[id] = photo; return }
#endif
        try await client.from("fit_check_worn_looks")
            .upsert(["fit_check_id": id, "photo_id": photo]).execute()
    }

    static func answeredPosts(_ items: [FeedItemDTO], viewer: UUID) async throws -> Set<UUID> {
        guard !items.isEmpty else { return [] }
#if DEBUG
        if SampleData.isActive {
            return Set(items.filter { SampleData.votes(fitCheckId: $0.id).contains { $0.voterId == viewer } }.map(\.id))
        }
#endif
        struct Row: Decodable { let fitCheckId: UUID }
        let rows: [Row] = try await client.from("fit_check_votes").select("fit_check_id")
            .eq("voter_id", value: viewer).in("fit_check_id", values: items.map(\.id)).execute().value
        return Set(rows.map(\.fitCheckId))
    }

    private struct OwnVoteRow: Decodable {
        let photoId: UUID
    }

    private struct ResultsParams: Encodable {
        let pFitCheckId: UUID
    }

    static func fetchVoteSummary(fitCheckId: UUID, voterId: UUID, creatorId: UUID,
                                 expiresAt: Date?) async throws -> VoteSummary {
#if DEBUG
        if SampleData.isActive {
            return sampleVoteSummary(fitCheckId: fitCheckId, voterId: voterId)
        }
#endif
        let myVote = try await fetchOwnVote(fitCheckId: fitCheckId, voterId: voterId)
        let isEnded = expiresAt.map { $0 <= Date() } ?? false
        let plan = VoteSummaryPlan.decide(isEnded: isEnded,
                                          isCreator: voterId == creatorId,
                                          hasVoted: myVote != nil)
        guard plan != .hidden else { return .hidden(myVote: nil) }
        return try await loadSummary(plan: plan, fitCheckId: fitCheckId, myVote: myVote,
                                     isCreator: voterId == creatorId)
    }

    private static func loadSummary(plan: VoteSummaryPlan, fitCheckId: UUID, myVote: UUID?,
                                    isCreator: Bool) async throws -> VoteSummary {
        guard plan == .closed else {
            return .from(tally: try await fetchLiveVoteTally(fitCheckId: fitCheckId), myVote: myVote)
        }
        let closed = try await fetchClosedResults(fitCheckId: fitCheckId)
        switch closedTallyOutcome(closed: closed, isCreator: isCreator, hasVoted: myVote != nil) {
        case .revealed:
            return .from(tally: closed, myVote: myVote)
        case .useLiveTally:
            return .from(tally: try await fetchLiveVoteTally(fitCheckId: fitCheckId), myVote: myVote)
        case .stayHidden:
            return .hidden(myVote: myVote)
        }
    }

    enum ClosedTallyOutcome: Equatable { case revealed, useLiveTally, stayHidden }

    /// `get_fit_check_results` returns rows only once the server considers the post ended.
    /// The caller picked it from the device clock, so an empty answer may mean the clock
    /// is ahead. A creator or voter may see the live tally either way; anyone else stays
    /// hidden rather than being shown a false "0 votes".
    static func closedTallyOutcome(closed: [LivePhotoTally], isCreator: Bool, hasVoted: Bool) -> ClosedTallyOutcome {
        if !closed.isEmpty { return .revealed }
        return isCreator || hasVoted ? .useLiveTally : .stayHidden
    }

    private static func fetchOwnVote(fitCheckId: UUID, voterId: UUID) async throws -> UUID? {
        let rows: [OwnVoteRow] = try await client.from("fit_check_votes")
            .select("photo_id")
            .eq("fit_check_id", value: fitCheckId)
            .eq("voter_id", value: voterId)
            .limit(1)
            .execute().value
        return rows.first?.photoId
    }

    /// `get_fit_check_results`: closed posts only.
    private static func fetchClosedResults(fitCheckId: UUID) async throws -> [LivePhotoTally] {
        try await client.rpc("get_fit_check_results", params: ResultsParams(pFitCheckId: fitCheckId))
            .execute().value
    }

#if DEBUG
    private static func sampleVoteSummary(fitCheckId: UUID, voterId: UUID) -> VoteSummary {
        .from(votes: SampleData.votes(fitCheckId: fitCheckId), voterId: voterId, myVote: nil)
    }
#endif
}
