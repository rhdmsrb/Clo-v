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
    @ScaledMetric(relativeTo: .body) private var tabIconSize: CGFloat = 17

    private static let labelMinScale: CGFloat = 0.7
    private static let chipSpacing: CGFloat = 6
    private static let iconLabelSpacing: CGFloat = 2
    /// Beyond this size the icons are dropped so the stacked chip never outgrows its height.
    private static let iconHiddenFrom: DynamicTypeSize = .xLarge

    var body: some View {
        HStack(spacing: Self.chipSpacing) {
            tabChip(.feed, label: "Feed", systemImage: "house")
                .accessibilityIdentifier("feedTab")
            tabChip(.groups, label: "Group", systemImage: "person.3")
                .accessibilityIdentifier("groupsTab")

            createButton

            tabChip(.search, label: "Search", systemImage: "magnifyingglass", hasFilledVariant: false)
                .accessibilityIdentifier("searchTab")
            tabChip(.account, label: "Profile", systemImage: "person")
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

    /// Icon above label, the layout people already know from other apps. The
    /// selected tab gets a soft fill and a filled icon; the others have no outline.
    @ViewBuilder
    private func tabChip(_ target: MainTab, label: String, systemImage: String, hasFilledVariant: Bool = true) -> some View {
        let isSelected = selection == target
        let showsIcon = dynamicTypeSize < Self.iconHiddenFrom
        let iconName = isSelected && hasFilledVariant ? "\(systemImage).fill" : systemImage
        Button { onSelect(target) } label: {
            VStack(spacing: Self.iconLabelSpacing) {
                if showsIcon {
                    Image(systemName: iconName)
                        .font(.system(size: tabIconSize, weight: isSelected ? .semibold : .regular))
                        .frame(height: tabIconSize + 2)
                }
                Text(label)
                    .font(Theme.font(.caption2, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(Self.labelMinScale)
            }
            .foregroundStyle(isSelected ? Theme.accentDeep : Theme.mutedForeground)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: chipHeight, maxHeight: chipHeight)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Theme.accentTint)
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
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
