import Foundation
import Supabase

/// Rolling out the 20261107* columns (tags, like_count, per-photo
/// description/tags) must not break the feed on a database that lacks them.
/// Mirrors how `attachVotePrompts` degrades for older deployments.
extension API {
    /// Remembers that the server rejected the extended column list so later
    /// requests skip the doomed first attempt.
    private actor FeedSchemaSupport {
        static let shared = FeedSchemaSupport()
        private(set) var supportsExtendedColumns = true
        func markUnsupported() { supportsExtendedColumns = false }
    }

    /// Runs `fetch` with the extended feed columns; if the server reports a
    /// missing column, retries once with the legacy column list.
    static func selectingFeedColumns<T>(_ fetch: (String) async throws -> T) async throws -> T {
        guard await FeedSchemaSupport.shared.supportsExtendedColumns else {
            return try await fetch(legacyFeedColumns)
        }
        do {
            return try await fetch(feedColumns)
        } catch {
            guard isMissingColumnError(error) else { throw error }
            Log.app.error("Feed columns missing on server; falling back to legacy list: \(error.localizedDescription)")
            await FeedSchemaSupport.shared.markUnsupported()
            return try await fetch(legacyFeedColumns)
        }
    }

    private static let missingSchemaCodes: Set<String> = ["42703", "42883", "PGRST202", "PGRST204"]

    /// The server lacks a column or function the client asked for, judged only
    /// by structured PostgREST/Postgres codes: undefined_column (42703),
    /// undefined_function (42883), PGRST202 (no function for the given params)
    /// and PGRST204 (column not in the schema cache, on writes). Message text
    /// is never inspected, so relationship errors (PGRST200) and transient
    /// failures never trigger a fallback or latch the feed downgrade.
    static func isMissingColumnError(_ error: Error) -> Bool {
        guard let code = (error as? PostgrestError)?.code else { return false }
        return missingSchemaCodes.contains(code)
    }
}
