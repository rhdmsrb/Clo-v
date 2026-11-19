import SwiftUI

/// Quick filters above the Explore grid: a row of occasion chips (Popular means no
/// occasion) and a row of color swatches. Both write into the same `ExploreFilter` the
/// Filters sheet edits: an occasion chip sets `occasion`, a swatch sets `tag` to the
/// color's name. Tapping the selected swatch again clears it.
struct ExploreQuickFilters: View {
    let filter: ExploreFilter
    let onChange: (ExploreFilter) -> Void

    struct Swatch: Identifiable {
        let name: String
        let color: Color
        var id: String { name }
    }

    static let swatches: [Swatch] = [
        Swatch(name: "white", color: .white), Swatch(name: "black", color: .black),
        Swatch(name: "blue", color: Color(red: 0.29, green: 0.56, blue: 0.89)),
        Swatch(name: "green", color: Color(red: 0.42, green: 0.73, blue: 0.36)),
        Swatch(name: "yellow", color: Color(red: 0.96, green: 0.90, blue: 0.30)),
        Swatch(name: "orange", color: Color(red: 0.93, green: 0.55, blue: 0.24)),
        Swatch(name: "red", color: Color(red: 0.88, green: 0.29, blue: 0.31)),
        Swatch(name: "pink", color: Color(red: 0.93, green: 0.47, blue: 0.67)),
        Swatch(name: "purple", color: Color(red: 0.62, green: 0.40, blue: 0.91)),
        Swatch(name: "brown", color: Color(red: 0.58, green: 0.40, blue: 0.24)),
        Swatch(name: "beige", color: Color(red: 0.96, green: 0.86, blue: 0.70)),
        Swatch(name: "gray", color: Color(white: 0.6))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s) {
                    FilterChip(title: "Popular", systemImage: "flame", isSelected: filter.occasion == nil) {
                        select(occasion: nil)
                    }
                    .accessibilityIdentifier("explore.chip.popular")
                    ForEach(ExploreFilter.occasions, id: \.self) { occasion in
                        FilterChip(title: occasion, isSelected: filter.occasion == occasion) {
                            select(occasion: occasion)
                        }
                        .accessibilityIdentifier("explore.chip.\(occasion)")
                    }
                }
                .padding(.horizontal, Spacing.l - Spacing.xs)
            }
            .scrollClipDisabled()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Self.swatches) { swatch in
                        SwatchChip(name: swatch.name.capitalized, color: swatch.color,
                                   isSelected: filter.tag?.lowercased() == swatch.name) {
                            select(tag: swatch.name)
                        }
                        .accessibilityIdentifier("explore.swatch.\(swatch.name)")
                    }
                }
                .padding(.horizontal, Spacing.sm)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Colors")
        }
    }

    private func select(occasion: String?) {
        var next = filter
        next.occasion = occasion
        onChange(next)
    }

    private func select(tag: String) {
        var next = filter
        next.tag = filter.tag?.lowercased() == tag ? nil : tag
        onChange(next)
    }
}

#Preview("Explore quick filters") {
    ExploreQuickFilters(filter: ExploreFilter(), onChange: { _ in })
        .padding(.vertical, Spacing.m)
        .background(Theme.card)
}
