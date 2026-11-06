import Foundation

/// The user's last few searches, newest first. A value type: every change
/// returns a new list, so it is trivial to test and safe to hold in `@State`.
struct RecentSearches: Equatable, Codable {
    static let limit = 8
    private static let minimumLength = 2

    private(set) var terms: [String]

    init(terms: [String] = []) {
        self.terms = Self.normalized(terms)
    }

    /// Puts `raw` first, dropping an earlier copy (ignoring case). Blank or
    /// one-character terms are ignored.
    func adding(_ raw: String) -> RecentSearches {
        let term = SearchTerm.sanitized(raw)
        guard term.count >= Self.minimumLength else { return self }
        return RecentSearches(terms: [term] + terms.filter { !Self.matches($0, term) })
    }

    func removing(_ raw: String) -> RecentSearches {
        RecentSearches(terms: terms.filter { !Self.matches($0, raw) })
    }

    func cleared() -> RecentSearches { RecentSearches() }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private static func normalized(_ terms: [String]) -> [String] {
        Array(terms.prefix(limit))
    }
}

/// Persists `RecentSearches` per signed-in user, so a shared device never
/// shows one person's searches to another.
struct RecentSearchStore {
    var defaults: UserDefaults = .standard

    func key(for userId: UUID) -> String { "clov.recentSearches.v1.\(userId.uuidString)" }

    func load(for userId: UUID) -> RecentSearches {
        guard let data = defaults.data(forKey: key(for: userId)) else { return RecentSearches() }
        do {
            return try JSONDecoder().decode(RecentSearches.self, from: data)
        } catch {
            Log.app.error("Reading recent searches failed: \(error.localizedDescription)")
            return RecentSearches()
        }
    }

    func save(_ searches: RecentSearches, for userId: UUID) {
        do {
            defaults.set(try JSONEncoder().encode(searches), forKey: key(for: userId))
        } catch {
            Log.app.error("Saving recent searches failed: \(error.localizedDescription)")
        }
    }
}
