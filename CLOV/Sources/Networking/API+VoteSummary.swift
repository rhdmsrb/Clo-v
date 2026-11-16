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
        do {
            return try await loadSummary(plan: plan, fitCheckId: fitCheckId, myVote: myVote,
                                         isCreator: voterId == creatorId)
        } catch where isMissingFunctionError(error) {
            // RPC not deployed yet: derive from whatever rows the vote policy exposes.
            return try await legacyVoteSummary(fitCheckId: fitCheckId, voterId: voterId, myVote: myVote)
        }
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

    /// True for undefined_function (42883) and PGRST202 only.
    static func isMissingFunctionError(_ error: Error) -> Bool {
        guard let code = (error as? PostgrestError)?.code else { return false }
        return code == "42883" || code == "PGRST202"
    }

    /// Caller has already passed the reveal rule (ended, creator, or voted).
    private static func legacyVoteSummary(fitCheckId: UUID, voterId: UUID, myVote: UUID?) async throws -> VoteSummary {
        let rows: [VoteRef] = try await client.from("fit_check_votes")
            .select("photo_id, voter_id")
            .eq("fit_check_id", value: fitCheckId)
            .execute().value
        return VoteSummary.from(votes: rows, voterId: voterId, myVote: myVote)
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
