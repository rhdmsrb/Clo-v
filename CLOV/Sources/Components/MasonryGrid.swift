import SwiftUI

/// Two-column staggered grid. Tile heights come from each item's aspect ratio
/// (width / height). Put it inside the caller's ScrollView.
struct MasonryGrid<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    var spacing: CGFloat = 12
    let aspectRatio: (Item) -> CGFloat
    let onTap: (Item) -> Void
    @ViewBuilder let tile: (Item) -> Tile

    private var columns: [[Item]] {
        MasonryLayout.assign(aspectRatios: items.map(aspectRatio))
            .map { $0.map { items[$0] } }
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                LazyVStack(spacing: spacing) {
                    ForEach(column) { item in
                        Button { onTap(item) } label: {
                            tile(item)
                                .aspectRatio(MasonryLayout.clampedRatio(aspectRatio(item)), contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                        }
                        .buttonStyle(InstantPressStyle())
                    }
                }
            }
        }
        .accessibilityIdentifier("masonry-grid")
    }
}

#Preview("MasonryGrid") {
    struct Sample: Identifiable { let id: Int; let ratio: CGFloat }
    let items = [0.75, 1.0, 0.6, 1.4, 0.8, 1.0].enumerated().map { Sample(id: $0.offset, ratio: $0.element) }
    return ScrollView {
        MasonryGrid(items: items, aspectRatio: { $0.ratio }, onTap: { _ in }) { item in
            Theme.accentTint.overlay(Text("\(item.id)").foregroundStyle(Theme.ink))
        }
        .padding()
    }
}
