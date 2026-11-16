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
            let tally = plan == .closed
                ? try await fetchClosedResults(fitCheckId: fitCheckId)
                : try await fetchLiveVoteTally(fitCheckId: fitCheckId)
            return .from(tally: tally, myVote: myVote)
        } catch where isMissingFunctionError(error) {
            // RPC not deployed yet: derive from whatever rows the vote policy exposes.
            return try await legacyVoteSummary(fitCheckId: fitCheckId, voterId: voterId, myVote: myVote)
        }
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
