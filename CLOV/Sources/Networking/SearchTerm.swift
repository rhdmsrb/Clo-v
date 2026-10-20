import Foundation

/// Makes user-typed search text safe to interpolate into a PostgREST
/// `.or("col.ilike.%…%")` filter string. Commas, parentheses, `%`, `*`,
/// quotes and backslashes are filter syntax there, so an unsanitized term
/// could append its own conditions (e.g. probe columns that aren't selected).
enum SearchTerm {
    static let maxLength = 50

    private static let allowedPunctuation: Set<Character> = [" ", "_", "-", "."]

    static func sanitized(_ raw: String) -> String {
        let kept = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isLetter || $0.isNumber || allowedPunctuation.contains($0) }
        return String(kept.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
    }
}
