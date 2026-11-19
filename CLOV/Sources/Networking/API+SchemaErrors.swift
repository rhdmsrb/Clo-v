import Foundation
import Supabase

extension API {
    private static let missingSchemaCodes: Set<String> = ["42703", "42883", "PGRST202", "PGRST204"]

    /// The server lacks a column or function the client asked for, judged only
    /// by structured PostgREST/Postgres codes: undefined_column (42703),
    /// undefined_function (42883), PGRST202 (no function for the given params)
    /// and PGRST204 (column not in the schema cache, on writes). Message text
    /// is never inspected, so relationship errors (PGRST200) and transient
    /// failures never trigger a fallback. Used by the create-post flow.
    static func isMissingColumnError(_ error: Error) -> Bool {
        guard let code = (error as? PostgrestError)?.code else { return false }
        return missingSchemaCodes.contains(code)
    }
}
