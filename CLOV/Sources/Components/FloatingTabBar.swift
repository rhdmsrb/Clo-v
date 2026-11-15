import SwiftUI

enum MainTab: Hashable {
    case feed, groups, search, account
}

/// Keep the core loops visible in one thumb-reachable navigation bar.
/// One opaque pill holding oval chips (Feed, Group, Search, Profile) and a
/// flat circular Post button in the centre, per the hand sketch. The selected
/// chip fills with a sliding capsule; the others are outlined.
struct FloatingTabBar: View {
    let selection: MainTab
    let onSelect: (MainTab) -> Void
    let onCreate: () -> Void

    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var chipHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var createIconSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 14

    private static let labelMinScale: CGFloat = 0.7
    private static let chipSpacing: CGFloat = 6
    private static let outlineWidth: CGFloat = 1
    /// Beyond this size the Search icon is dropped so labels never truncate.
    private static let iconHiddenFrom: DynamicTypeSize = .xLarge

    var body: some View {
        HStack(spacing: Self.chipSpacing) {
            tabChip(.feed, label: "Feed")
                .accessibilityIdentifier("feedTab")
            tabChip(.groups, label: "Group", showsBadge: true)
                .accessibilityIdentifier("groupsTab")

            createButton

            tabChip(.search, label: "Search", systemImage: "magnifyingglass")
                .accessibilityIdentifier("searchTab")
            tabChip(.account, label: "Profile")
                .accessibilityIdentifier("accountTab")
        }
        .motionSafeAnimation(Theme.quick, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Theme.cardElevated, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        }
        .overlay {
            if contrast == .increased {
                Capsule(style: .continuous).strokeBorder(Theme.controlBorder, lineWidth: 1)
            }
        }
        .elevatedShadow()
    }

    private var createButton: some View {
        Button(action: onCreate) {
            Image(systemName: "plus")
                .font(.system(size: createIconSize, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: chipHeight, height: chipHeight)
                .background(Theme.heroGradient, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(PostPressStyle())
        .accessibilityIdentifier("tabPlusButton")
        .accessibilityLabel("Post a Fit-Check")
        .accessibilityShowsLargeContentViewer {
            Label("Post a Fit-Check", systemImage: "plus")
        }
    }

    @ViewBuilder
    private func tabChip(_ target: MainTab, label: String, systemImage: String? = nil, showsBadge: Bool = false) -> some View {
        let isSelected = selection == target
        let showsIcon = systemImage != nil && dynamicTypeSize < Self.iconHiddenFrom
        Button { onSelect(target) } label: {
            HStack(spacing: 4) {
                if showsIcon, let systemImage {
                    Image(systemName: systemImage)
                        .font(Theme.font(.caption, weight: .semibold))
                }
                Text(label)
                    .font(Theme.font(.caption, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(Self.labelMinScale)
            }
            .foregroundStyle(isSelected ? Theme.accentDeep : Theme.mutedForeground)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: chipHeight, maxHeight: chipHeight)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .strokeBorder(Theme.controlBorder.opacity(isSelected ? 0 : 0.6), lineWidth: Self.outlineWidth)
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Theme.accentTint)
                            .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                    }
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(TabPressStyle())
        .overlay(alignment: .topTrailing) {
            if showsBadge { plusBadge }
        }
        // Pin the label so VoiceOver reads just the tab name (no auto-generated
        // symbol description) and label-based automation keeps working.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(label, systemImage: systemImage ?? "circle")
        }
    }

    /// Decorative corner badge (not wired to unread state yet).
    private var plusBadge: some View {
        Image(systemName: "plus")
            .font(.system(size: badgeSize * 0.55, weight: .heavy))
            .foregroundStyle(Theme.accentDeep)
            .frame(width: badgeSize, height: badgeSize)
            .background(Theme.cardElevated, in: Circle())
            .overlay(Circle().strokeBorder(Theme.accentDeep, lineWidth: 1))
            .offset(x: -2, y: -2)
            .accessibilityHidden(true)
    }
}

private struct PostPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .motionSafeAnimation(value: configuration.isPressed)
    }
}

/// Acknowledges a tab touch immediately, before the selection pill moves.
private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .motionSafeAnimation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
