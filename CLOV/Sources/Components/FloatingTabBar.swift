import SwiftUI

enum MainTab: Hashable {
    case feed, groups, search, account
}

/// Floating bottom bar: Feed · Group · (Post) · Search · Profile. A white capsule with
/// a soft shadow; the selected tab's icon turns accent and fills. Post is an emphasised
/// black circle in the centre that opens Create.
struct FloatingTabBar: View {
    let selection: MainTab
    let onSelect: (MainTab) -> Void
    let onCreate: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var itemHeight: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var postSize: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var postIconSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var tabIconSize: CGFloat = 19

    private static let labelMinScale: CGFloat = 0.7
    private static let iconLabelSpacing: CGFloat = 3
    /// Beyond this size the icons are dropped so the stacked item never outgrows its height.
    private static let iconHiddenFrom: DynamicTypeSize = .xLarge

    var body: some View {
        HStack(spacing: Spacing.xs) {
            tabItem(.feed, label: "Feed", systemImage: "house")
                .accessibilityIdentifier("feedTab")
            tabItem(.groups, label: "Group", systemImage: "person.3")
                .accessibilityIdentifier("groupsTab")

            createButton

            tabItem(.search, label: "Search", systemImage: "magnifyingglass", hasFilledVariant: false)
                .accessibilityIdentifier("searchTab")
            tabItem(.account, label: "Profile", systemImage: "person")
                .accessibilityIdentifier("accountTab")
        }
        .motionSafeAnimation(Theme.quick, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs + 2)
        .background(Theme.cardElevated, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(contrast == .increased ? Theme.controlBorder : Theme.line.opacity(0.06), lineWidth: 1)
        }
        .elevatedShadow()
    }

    private var createButton: some View {
        Button(action: onCreate) {
            Image(systemName: "plus")
                .font(.system(size: postIconSize, weight: .semibold))
                .foregroundStyle(Theme.primaryButtonText)
                .frame(width: postSize, height: postSize)
                .background(Theme.primaryButtonFill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PostPressStyle())
        .padding(.horizontal, Spacing.xs)
        .accessibilityIdentifier("tabPlusButton")
        .accessibilityLabel("Post a Fit-Check")
        .accessibilityShowsLargeContentViewer {
            Label("Post a Fit-Check", systemImage: "plus")
        }
    }

    /// Icon above label. The selected tab fills its icon in the accent and bolds its label.
    @ViewBuilder
    private func tabItem(_ target: MainTab, label: String, systemImage: String,
                         hasFilledVariant: Bool = true) -> some View {
        let isSelected = selection == target
        let showsIcon = dynamicTypeSize < Self.iconHiddenFrom
        Button { onSelect(target) } label: {
            VStack(spacing: Self.iconLabelSpacing) {
                if showsIcon {
                    Image(systemName: isSelected && hasFilledVariant ? "\(systemImage).fill" : systemImage)
                        .font(.system(size: tabIconSize, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.mutedForeground)
                        .frame(height: tabIconSize + 4)
                }
                Text(label)
                    .font(Theme.font(.caption2, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Theme.accentDeep : Theme.mutedForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(Self.labelMinScale)
            }
            .frame(maxWidth: .infinity, minHeight: itemHeight, maxHeight: itemHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle())
        // Pin the label so VoiceOver reads just the tab name (no auto-generated
        // symbol description) and label-based automation keeps working.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(label, systemImage: systemImage)
        }
    }
}

private struct PostPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .motionSafeAnimation(value: configuration.isPressed)
    }
}

/// Acknowledges a tab touch immediately, before the selection changes.
private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .motionSafeAnimation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

#Preview("Tab bar") {
    struct Demo: View {
        @State private var tab: MainTab = .feed
        var body: some View {
            VStack {
                Spacer()
                FloatingTabBar(selection: tab, onSelect: { tab = $0 }, onCreate: {})
                    .padding(.horizontal, Spacing.m)
            }
            .background(Theme.background)
        }
    }
    return Demo()
}
