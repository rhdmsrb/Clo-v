import SwiftUI

/// One option in a `FilterChipRow`.
struct FilterOption: Identifiable, Hashable {
    let id: String
    let title: String
    var systemImage: String? = nil
}

/// Pill filter chip. Only the selected chip is filled (accent); the rest are outlined.
/// Built on the shared `ChipButtonStyle`, so it matches chips elsewhere in the app.
struct FilterChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var visualHeight: CGFloat = 36

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: Spacing.xs + 2) {
                if let systemImage { Image(systemName: systemImage).imageScale(.small) }
                Text(title).lineLimit(1)
            }
            .font(Theme.font(.subheadline, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Theme.accentForeground : Theme.ink)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: visualHeight)
            .background(isSelected ? Theme.accent : Theme.card, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Theme.controlBorder, lineWidth: 1)
            }
            // The pill looks slim, but the tap area keeps the 44pt minimum.
            .frame(minHeight: Theme.minTapSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .motionSafeAnimation(Theme.quick, value: isSelected)
    }
}

/// Horizontally scrolling row of filter chips with single selection.
struct FilterChipRow: View {
    let options: [FilterOption]
    @Binding var selection: String
    var accessibilityLabel = "Filters"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(options) { option in
                    FilterChip(title: option.title, systemImage: option.systemImage,
                               isSelected: option.id == selection) { selection = option.id }
                        .accessibilityIdentifier("filter.\(option.id)")
                }
            }
            .padding(.horizontal, Spacing.pageGutter)
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Round color swatch filter. Selected swatches get an ink ring and a check.
struct SwatchChip: View {
    let name: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    private static let size: CGFloat = 28
    private static let ringGap: CGFloat = 3

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: Self.size, height: Self.size)
                .overlay(Circle().strokeBorder(Theme.controlBorder, lineWidth: 1))
                .padding(Self.ringGap)
                .overlay {
                    if isSelected { Circle().strokeBorder(Theme.ink, lineWidth: 1.5) }
                }
                .frame(minWidth: Theme.minTapSize, minHeight: Theme.minTapSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview("Filter chips") {
    struct Demo: View {
        @State private var selection = "popular"
        @State private var swatch = "black"
        let options = [
            FilterOption(id: "popular", title: "Popular", systemImage: "flame"),
            FilterOption(id: "new", title: "New"),
            FilterOption(id: "following", title: "Following"),
            FilterOption(id: "streetwear", title: "Streetwear"),
            FilterOption(id: "minimal", title: "Minimal")
        ]
        let swatches: [(String, Color)] = [("white", .white), ("black", .black), ("denim", .blue), ("olive", .green), ("camel", .brown)]

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.m) {
                FilterChipRow(options: options, selection: $selection)
                HStack(spacing: 0) {
                    ForEach(swatches, id: \.0) { name, color in
                        SwatchChip(name: name, color: color, isSelected: swatch == name) { swatch = name }
                    }
                }
                .padding(.horizontal, Spacing.s)
            }
            .padding(.vertical, Spacing.m)
            .background(Theme.background)
        }
    }
    return Demo()
}
