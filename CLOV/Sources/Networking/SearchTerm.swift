import Foundation

/// Makes user-typed search text safe to interpolate into a PostgREST
/// `.or("col.ilike.%…%")` filter string. Commas, parentheses, `%`, `*`,
/// quotes and backslashes are filter syntax there, so an unsanitized term
/// could append its own conditions (e.g. probe columns that aren't selected).
enum SearchTerm {
    static let maxLength = 50

    private static let allowedPunctuation: Set<Character> = [" ", "_", "-", "."]

    /// Escapes `\`, `%` and `_` so user text matches literally inside a LIKE/ILIKE pattern.
    static func likeEscaped(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    static func sanitized(_ raw: String) -> String {
        let kept = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isLetter || $0.isNumber || allowedPunctuation.contains($0) }
        return String(kept.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }
}
