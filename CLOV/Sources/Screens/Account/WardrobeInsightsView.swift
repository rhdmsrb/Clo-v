@preconcurrency import SwiftUI
import Charts

/// Wardrobe insights: what the wardrobe is made of (donut by category, color,
/// brand, season or tag), what it is worth and how often pieces get worn.
@MainActor
struct WardrobeInsightsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var items: [WardrobeItem] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?
    @State private var dimension: InsightDimension = .category
    @State private var category: WardrobeCategory?

    private static let donutHeight: CGFloat = 260
    private static let donutInnerRatio: CGFloat = 0.62
    private static let legendSwatch: CGFloat = 14

    private var insights: WardrobeInsights { WardrobeInsights(items: items).filtered(by: category) }

    var body: some View {
        ScrollView {
            AsyncStateView(isLoading: isLoading, error: error, topPadding: Spacing.l,
                           hasLoaded: hasLoaded, retry: { await load() }) {
                if items.isEmpty {
                    EmptyStateView(icon: "chart.pie", title: "No pieces yet",
                                   message: "Add clothes to your wardrobe to see what you own, what it's worth and what you wear.")
                        .padding(.top, Spacing.xl)
                } else {
                    content
                }
            }
            .padding(20)
        }
        .clearsTabBar()
        .background(Theme.background)
        .navigationTitle("Wardrobe insights")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .revisionTask(appState.contentRevision) { await load() }
        .accessibilityIdentifier("wardrobeInsights.screen")
    }

    private var content: some View {
        let insights = insights
        let slices = insights.slices(by: dimension)
        return VStack(alignment: .leading, spacing: Spacing.l) {
            dimensionPicker
            donut(slices: slices, itemCount: insights.items.count)
            categoryFilter
            legend(slices)
            WardrobeValueCards(insights: insights)
            WardrobeRankedSections(insights: insights)
        }
        .animation(reduceMotion ? nil : .snappy, value: dimension)
        .animation(reduceMotion ? nil : .snappy, value: category)
    }

    // MARK: Pickers

    private var dimensionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(InsightDimension.allCases) { option in
                    chip(option.label, isSelected: dimension == option, id: "dimension.\(option.rawValue)") {
                        dimension = option
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Group by")
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                chip("All", isSelected: category == nil, id: "category.all") { category = nil }
                ForEach(WardrobeCategory.allCases) { option in
                    chip(option.label, isSelected: category == option, id: "category.\(option.rawValue)") {
                        category = option
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter by category")
    }

    private func chip(_ title: String, isSelected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            Haptics.selection()
            action()
        }
        .buttonStyle(ChipButtonStyle(isSelected: isSelected, font: Theme.label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("wardrobeInsights.\(id)")
    }

    // MARK: Donut

    private func donut(slices: [InsightSlice], itemCount: Int) -> some View {
        ZStack {
            if slices.isEmpty {
                Circle()
                    .stroke(Theme.muted, lineWidth: Self.donutHeight * (1 - Self.donutInnerRatio) / 2)
                    .padding(Self.donutHeight * (1 - Self.donutInnerRatio) / 4)
            } else {
                Chart(slices) { slice in
                    SectorMark(angle: .value("Pieces", slice.count),
                               innerRadius: .ratio(Self.donutInnerRatio),
                               angularInset: slices.count > 1 ? 1.5 : 0)
                        .foregroundStyle(InsightPalette.color(at: index(of: slice, in: slices)))
                }
                .chartLegend(.hidden)
            }
            VStack(spacing: Spacing.xs) {
                Text("\(itemCount) \(itemCount == 1 ? "piece" : "pieces")")
                    .font(Theme.editorialFont(size: 26, relativeTo: .title2))
                    .foregroundStyle(Theme.ink)
                Text("in \(slices.count) \(dimension.countNoun(slices.count))")
                    .font(Theme.font(.subheadline))
                    .foregroundStyle(Theme.mutedForeground)
            }
            .multilineTextAlignment(.center)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .frame(height: Self.donutHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(itemCount) pieces by \(dimension.label.lowercased())")
        .accessibilityValue(slices.map { "\($0.label) \($0.count)" }.joined(separator: ", "))
        .accessibilityIdentifier("wardrobeInsights.chart")
    }

    private func index(of slice: InsightSlice, in slices: [InsightSlice]) -> Int {
        slices.firstIndex(of: slice) ?? 0
    }

    // MARK: Legend

    private func legend(_ slices: [InsightSlice]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if slices.isEmpty {
                Text("No pieces in this category yet.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.mutedForeground)
            }
            ForEach(Array(slices.enumerated()), id: \.element.id) { offset, slice in
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(InsightPalette.color(at: offset))
                        .frame(width: Self.legendSwatch, height: Self.legendSwatch)
                        .accessibilityHidden(true)
                    Text(slice.label)
                        .font(Theme.body)
                        .foregroundStyle(Theme.ink)
                    Text(slice.count.formatted())
                        .font(Theme.bodyEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: Spacing.s)
                    Text(slice.share.formatted(.percent.precision(.fractionLength(0))))
                        .font(Theme.body)
                        .monospacedDigit()
                        .foregroundStyle(Theme.mutedForeground)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("wardrobeInsights.legend")
    }

    // MARK: Loading

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            items = try await API.fetchWardrobeItems(ownerId: appState.userId)
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            Log.app.error("Load wardrobe insights failed: \(error.localizedDescription)")
            self.error = "Couldn't load your wardrobe insights. Please try again."
        }
    }
}

/// Categorical colors for the donut, distinguishable in light and dark mode.
/// Past the last color the palette repeats; the legend still names each slice.
enum InsightPalette {
    static let colors: [Color] = [
        Theme.adaptive(hex: 0x8FB8F2, 0x7AA6E8),
        Theme.adaptive(hex: 0xE2552B, 0xFF7A4D),
        Theme.adaptive(hex: 0x2A8F6C, 0x7FE0B8),
        Theme.adaptive(hex: 0xE0A93B, 0xF2C66B),
        Theme.adaptive(hex: 0x6B5A7A, 0xC4B3D6),
        Theme.adaptive(hex: 0x3D6E8F, 0x8EC3E6),
        Theme.adaptive(hex: 0xB9677E, 0xE8A3B7),
        Theme.adaptive(hex: 0x7C8A3A, 0xC5D27E)
    ]

    static func color(at index: Int) -> Color { colors[index % colors.count] }
}
