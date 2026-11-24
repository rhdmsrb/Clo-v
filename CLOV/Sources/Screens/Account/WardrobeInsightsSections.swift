@preconcurrency import SwiftUI

/// "Wardrobe value" and "Average price" tiles, side by side.
struct WardrobeValueCards: View {
    let insights: WardrobeInsights
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            tiles
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            if insights.pricedItemCount < insights.items.count {
                Text(footnote)
                    .font(Theme.font(.footnote))
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
    }

    private var tiles: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0))
            : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            tile(icon: "banknote", value: insights.totalValue, title: "Wardrobe value", id: "totalValue")
            Divider().padding(.vertical, Spacing.m)
            tile(icon: "tshirt", value: insights.averagePrice, title: "Average price", id: "averagePrice")
        }
    }

    private var footnote: String {
        let missing = insights.items.count - insights.pricedItemCount
        return "\(missing) \(missing == 1 ? "piece has" : "pieces have") no price yet. Add one from Edit item in your wardrobe."
    }

    private func tile(icon: String, value: Decimal, title: String, id: String) -> some View {
        VStack(spacing: Spacing.s) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.mutedForeground)
                .accessibilityHidden(true)
            Text(PriceInput.formatted(value))
                .font(Theme.editorialFont(size: 26, relativeTo: .title2))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(Theme.font(.subheadline))
                .foregroundStyle(Theme.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(PriceInput.formatted(value))
        .accessibilityIdentifier("wardrobeInsights.\(id)")
    }
}

/// Ranked lists: highest price, most worn and best cost per wear.
struct WardrobeRankedSections: View {
    let insights: WardrobeInsights

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            section("Highest price", id: "highestPrice", items: insights.mostExpensive,
                    empty: "Add prices to your pieces to rank them here.") { item in
                item.price.map(PriceInput.formatted) ?? ""
            }
            section("Most worn", id: "mostWorn", items: insights.mostWorn,
                    empty: "Tap \"Wore it today\" on a piece to start tracking wears.") { item in
                let wears = item.wearCount ?? 0
                return "\(wears)×"
            }
            section("Best cost per wear", id: "costPerWear", items: insights.bestCostPerWear,
                    empty: "Pieces with a price and at least one wear show up here.") { item in
                WardrobeInsights.costPerWear(of: item).map { "\(PriceInput.formatted($0)) / wear" } ?? ""
            }
            if insights.neverWornCount > 0 {
                Label("\(insights.neverWornCount) \(insights.neverWornCount == 1 ? "piece hasn't" : "pieces haven't") been worn yet",
                      systemImage: "moon.zzz")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .softCard(radius: Theme.tileRadius, padding: 14)
                    .accessibilityIdentifier("wardrobeInsights.neverWorn")
            }
        }
    }

    private func section(_ title: String, id: String, items: [WardrobeItem], empty: String,
                         value: @escaping (WardrobeItem) -> String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: title)
                .accessibilityAddTraits(.isHeader)
            if items.isEmpty {
                Text(empty)
                    .font(Theme.font(.subheadline))
                    .foregroundStyle(Theme.mutedForeground)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                        if offset > 0 { Divider().padding(.leading, 68) }
                        RankedItemRow(rank: offset + 1, item: item, value: value(item))
                    }
                }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
            }
        }
        .accessibilityIdentifier("wardrobeInsights.\(id)")
    }
}

private struct RankedItemRow: View {
    let rank: Int
    let item: WardrobeItem
    let value: String

    private static let thumbnailSize: CGFloat = 44

    var body: some View {
        HStack(spacing: Spacing.sm) {
            WardrobePhoto(url: item.imageUrl)
                .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let brand = item.brand, !brand.isEmpty {
                    Text(brand)
                        .font(Theme.font(.footnote))
                        .foregroundStyle(Theme.mutedForeground)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.s)
            Text(value)
                .font(Theme.bodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank). \(title), \(value)")
    }

    private var title: String {
        if let name = item.name, !name.isEmpty { return name }
        return WardrobeCategory(rawValue: item.category)?.label ?? item.category.capitalized
    }
}
