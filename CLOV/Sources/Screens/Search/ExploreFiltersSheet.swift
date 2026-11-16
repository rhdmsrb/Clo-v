import SwiftUI

/// Occasion and sort choices for Explore. Edits a draft; Apply commits it.
struct ExploreFiltersSheet: View {
    let initial: ExploreFilter
    var availableTags: [String] = []
    let onApply: (ExploreFilter) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExploreFilter

    init(initial: ExploreFilter, availableTags: [String] = [], onApply: @escaping (ExploreFilter) -> Void) {
        self.initial = initial
        self.availableTags = availableTags
        self.onApply = onApply
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("Occasion") {
                        FlowLayout(spacing: 9) {
                            ChipToggle(label: "All", selected: draft.occasion == nil) { draft.occasion = nil }
                            ForEach(ExploreFilter.occasions, id: \.self) { value in
                                ChipToggle(label: value, selected: draft.occasion == value) { draft.occasion = value }
                            }
                        }
                    }
                    if !availableTags.isEmpty {
                        section("Tag") {
                            FlowLayout(spacing: 9) {
                                ChipToggle(label: "Any", selected: draft.tag == nil) { draft.tag = nil }
                                ForEach(availableTags, id: \.self) { value in
                                    ChipToggle(label: "#\(value)", selected: draft.tag == value) { draft.tag = value }
                                }
                            }
                        }
                    }
                    section("Sort by") {
                        HStack(spacing: 9) {
                            ForEach(ExploreSort.allCases) { option in
                                ChipToggle(label: option.title, selected: draft.sort == option) { draft.sort = option }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Apply") { onApply(draft); dismiss() }
                        .accessibilityIdentifier("explore.filters.apply")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset") { draft = ExploreFilter() }
                        .disabled(draft.isDefault)
                        .accessibilityIdentifier("explore.filters.reset")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title.uppercased()).font(Theme.micro).tracking(1.1).foregroundStyle(Theme.mutedForeground)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}
