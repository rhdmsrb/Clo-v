import Testing
@testable import CLOV

@Suite("Search empty state")
struct SearchNoResultsTests {
    private let ideas = ["Wedding guest", "Interview", "Date night", "Brunch", "Travel fit", "Streetwear"]

    @Test("The headline names the search")
    func headlineNamesTheSearch() {
        #expect(SearchNoResults.headline(term: "wedding guest") == "No looks for “wedding guest”")
    }

    @Test("Without a search, the headline talks about the filters")
    func headlineForFiltersOnly() {
        #expect(SearchNoResults.headline(term: "") == "No looks match these filters")
    }

    @Test("The suggestions leave out what was just searched, whatever its case or spacing")
    func alternativesSkipTheCurrentSearch() {
        let picks = SearchNoResults.alternatives(for: "  WEDDING guest ", from: ideas)
        #expect(!picks.contains("Wedding guest"))
        #expect(picks.first == "Interview")
    }

    @Test("At most five suggestions, in their original order")
    func alternativesAreCapped() {
        let picks = SearchNoResults.alternatives(for: "blazer", from: ideas)
        #expect(picks == Array(ideas.prefix(SearchNoResults.maxAlternatives)))
    }

    @Test("Clear filters names how many are on", arguments: [(1, "Clear filter"), (2, "Clear 2 filters")])
    func clearFiltersTitle(count: Int, title: String) {
        #expect(SearchNoResults.clearFiltersTitle(activeCount: count) == title)
    }
}
