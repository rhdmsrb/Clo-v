import SwiftUI

/// Wording and suggestion picking for the Explore empty state, unit tested.
enum SearchNoResults {
    static let maxAlternatives = 5

    static func headline(term: String) -> String {
        term.isEmpty ? "No looks match these filters" : "No looks for “\(term)”"
    }

    static let message = "Your circle hasn’t posted one yet. Browse something close instead."

    /// Search ideas other than the one that just came back empty, in their original order.
    static func alternatives(for term: String, from ideas: [String]) -> [String] {
        let current = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Array(ideas.filter { $0.lowercased() != current }.prefix(maxAlternatives))
    }

    static func clearFiltersTitle(activeCount: Int) -> String {
        activeCount > 1 ? "Clear \(activeCount) filters" : "Clear filter"
    }
}

/// Shown when a search or filter on Explore finds nothing: a serif headline naming the
/// search, then "Try instead" chips that run a new search, and a link to clear filters.
struct SearchNoResultsView: View {
    let term: String
    let activeFilterCount: Int
    let ideas: [String]
    let onSearch: (String) -> Void
    let onClearFilters: () -> Void

    private static let sectionGap: CGFloat = 22
    private static let chipTracking: CGFloat = 1.1

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(SearchNoResults.headline(term: term))
                .font(Theme.font(.title2, weight: .semibold))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("search.noResults.headline")
            Text(SearchNoResults.message)
                .font(Theme.font(.subheadline))
                .foregroundStyle(Theme.mutedForeground)
            alternatives
            if activeFilterCount > 0 { clearFiltersButton }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.l)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.noResults")
    }

    @ViewBuilder
    private var alternatives: some View {
        let picks = SearchNoResults.alternatives(for: term, from: ideas)
        if !picks.isEmpty {
            Text("TRY INSTEAD")
                .font(Theme.micro).tracking(Self.chipTracking)
                .foregroundStyle(Theme.mutedForeground)
                .padding(.top, Self.sectionGap)
                .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: Spacing.s) {
                ForEach(picks, id: \.self) { idea in
                    Button { onSearch(idea) } label: {
                        Label(idea, systemImage: "magnifyingglass")
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: false, font: Theme.label,
                                                 unselectedFill: Theme.accentTint, horizontalPadding: 14))
                    .accessibilityLabel("Search \(idea)")
                    .accessibilityIdentifier("search.noResults.suggestion_\(idea)")
                }
            }
        }
    }

    private var clearFiltersButton: some View {
        Button(action: onClearFilters) {
            Text("\(SearchNoResults.clearFiltersTitle(activeCount: activeFilterCount)) ›")
                .font(Theme.label)
                .foregroundStyle(Theme.accentDeep)
                .frame(minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.xs)
        .accessibilityLabel(SearchNoResults.clearFiltersTitle(activeCount: activeFilterCount))
        .accessibilityIdentifier("search.noResults.clearFilters")
    }
}

#Preview("Search no results") {
    SearchNoResultsView(term: "wedding guest", activeFilterCount: 2,
                        ideas: ["Wedding guest", "Date night", "Brunch", "Interview", "Travel fit", "Streetwear"],
                        onSearch: { _ in }, onClearFilters: {})
        .padding(20)
}
