import SwiftUI

enum MainTab: Hashable {
    case feed, search, activity, account
}

/// Keep the core loops visible in one thumb-reachable navigation bar.
/// Opaque elevated capsule (no blur under text), sliding selection pill,
/// and a gradient Post button rising above the bar.
struct FloatingTabBar: View {
    let selection: MainTab
    let onSelect: (MainTab) -> Void
    let onCreate: () -> Void

    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    @ScaledMetric(relativeTo: .body) private var tabIconSize: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var tabHitHeight: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var createDiameter: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var createIconSize: CGFloat = 22

    private static let labelMinScale: CGFloat = 0.7

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.feed, systemImage: "house", activeSystemImage: "house.fill", label: "For You")
                .accessibilityIdentifier("feedTab")
            tabButton(.search, systemImage: "magnifyingglass", activeSystemImage: "magnifyingglass", label: "Search")
                .accessibilityIdentifier("searchTab")

            createButton

            tabButton(.activity, systemImage: "bell", activeSystemImage: "bell.fill", label: "Activity")
                .accessibilityIdentifier("activityTab")

            tabButton(.account, systemImage: "person.crop.circle", activeSystemImage: "person.crop.circle.fill", label: "Profile")
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
            VStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.system(size: createIconSize, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: createDiameter, height: createDiameter)
                    .background(Theme.heroGradient, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                    .elevatedShadow()
                Text("Post")
                    .font(Theme.font(.caption2, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(Self.labelMinScale)
                    .foregroundStyle(Theme.ink)
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, minHeight: tabHitHeight, maxHeight: tabHitHeight, alignment: .bottom)
        }
        .buttonStyle(PostPressStyle())
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("tabPlusButton")
        .accessibilityLabel("Post a Fit-Check")
        .accessibilityShowsLargeContentViewer {
            Label("Post a Fit-Check", systemImage: "plus")
        }
    }

    @ViewBuilder
    private func tabButton(_ target: MainTab, systemImage: String, activeSystemImage: String, label: String) -> some View {
        let isSelected = selection == target
        Button { onSelect(target) } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? activeSystemImage : systemImage)
                    .font(.system(size: tabIconSize, weight: isSelected ? .semibold : .regular))
                    .symbolEffect(.bounce, options: .nonRepeating, value: isSelected && !reduceMotion)
                Text(label)
                    .font(Theme.font(.caption2, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(Self.labelMinScale)
            }
            .foregroundStyle(isSelected ? Theme.accentDeep : Theme.mutedForeground)
            .frame(maxWidth: .infinity, minHeight: tabHitHeight)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Theme.accentTint)
                        .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle())
        .frame(maxWidth: .infinity)
        // `.combine` alone would fold the SF Symbol's own auto-generated
        // description into the label too (e.g. "two people, Groups")
        // instead of leaving it exactly `label` — pin it explicitly so
        // VoiceOver reads just the tab name, and so tests/automation
        // that look up this button by its plain label keep working.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer {
            Label(label, systemImage: isSelected ? activeSystemImage : systemImage)
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
