import SwiftUI

/// Plain button style that acknowledges a touch immediately.
struct InstantPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .motionSafeAnimation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Circular header icon button: 44pt `cardElevated` container with a soft shadow.
struct FeedIconButton: View {
    let systemImage: String
    var tint: Color = Theme.ink
    let accessibilityLabel: String
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FeedIconBadge(systemImage: systemImage, tint: tint)
        }
        .buttonStyle(InstantPressStyle())
        .accessibilityLabel(accessibilityLabel)
        .modifier(OptionalIdentifier(identifier: accessibilityIdentifier))
    }
}

private struct OptionalIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

struct FeedIconBadge: View {
    let systemImage: String
    var tint: Color = Theme.ink

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 17

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: Theme.minTapSize, height: Theme.minTapSize)
            .background(Theme.cardElevated, in: Circle())
            .overlay(Circle().stroke(Theme.controlBorder.opacity(0.5), lineWidth: 1))
            .layeredShadow()
            .contentShape(Circle())
    }
}

struct FeedBellIcon: View {
    let unreadCount: Int

    private static let maxBadgeCount = 9
    private static let badgeMinSize: CGFloat = 18

    var body: some View {
        ZStack(alignment: .topTrailing) {
            FeedIconBadge(systemImage: "bell")
            if unreadCount > 0 {
                Text(unreadCount > Self.maxBadgeCount ? "\(Self.maxBadgeCount)+" : "\(unreadCount)")
                    .font(Theme.font(.caption2, weight: .bold))
                    .foregroundStyle(Theme.accentForeground)
                    .lineLimit(1)
                    .padding(4)
                    .frame(minWidth: Self.badgeMinSize, minHeight: Self.badgeMinSize)
                    .background(Theme.accent)
                    .clipShape(Circle())
                    .offset(x: 2, y: -2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unreadCount > 0 ? "Notifications, \(unreadCount) unread" : "Notifications")
    }
}

/// One segment of the For You / Following capsule. The selected pill slides
/// between segments through the shared matched-geometry namespace.
struct FeedModeChip: View {
    let label: String
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected && differentiate {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).accessibilityHidden(true)
                }
                Text(label).lineLimit(1)
            }
            .font(Theme.bodyEmphasis)
            .foregroundStyle(isSelected ? Theme.accentDeep : Theme.mutedForeground)
            .padding(.horizontal, 16)
            .frame(minHeight: Theme.minTapSize)
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Theme.accentTint)
                        .overlay(Capsule(style: .continuous).stroke(Theme.accentDeep, lineWidth: 1.5))
                        .matchedGeometryEffect(id: "feedModeIndicator", in: namespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(InstantPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("feedMode_\(label.replacingOccurrences(of: " ", with: ""))")
    }
}

/// Segmented capsule holding the mode chips.
struct FeedModeSegments: View {
    @Binding var mode: FeedMode
    let onSelect: (FeedMode) -> Void

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            FeedModeChip(label: "For You", isSelected: mode == .forYou, namespace: indicator) { onSelect(.forYou) }
            FeedModeChip(label: "Following", isSelected: mode == .following, namespace: indicator) { onSelect(.following) }
        }
        .padding(3)
        .background(Theme.muted, in: Capsule(style: .continuous))
        .motionSafeAnimation(Theme.quick, value: mode)
        .sensoryFeedback(.selection, trigger: mode)
    }
}

struct FeedOccasionChip: View {
    let label: String
    let symbol: String
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected && differentiate ? "checkmark" : symbol)
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(label).lineLimit(1)
            }
            .font(Theme.label)
            .foregroundStyle(isSelected ? Theme.accentDeep : Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: Theme.minTapSize)
            .background {
                Capsule(style: .continuous).fill(Theme.muted)
                    .overlay(Capsule(style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Theme.accentTint)
                        .overlay(Capsule(style: .continuous).stroke(Theme.accentDeep, lineWidth: 1.5))
                        .matchedGeometryEffect(id: "feedOccasionIndicator", in: namespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(InstantPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .motionSafeAnimation(Theme.quick, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// Sort control: circular icon button that opens the sort menu.
struct FeedSortMenu: View {
    @Binding var sort: FeedSortOption

    var body: some View {
        Menu {
            Button("Recommended", systemImage: "sparkles") { sort = .forYou }
            Button("Newest", systemImage: "clock") { sort = .newest }
            Button("Most voted", systemImage: "chart.bar.fill") { sort = .votes }
        } label: {
            FeedIconBadge(systemImage: "slider.horizontal.3")
        }
        .accessibilityLabel("Sort: \(sort.title)")
    }
}

/// Search field with a visible, high-contrast label above it.
struct FeedSearchField: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Search Fit-Checks")
                .font(Theme.label)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedForeground)
                    .accessibilityHidden(true)
                TextField("Search people, looks, occasions", text: $text, prompt:
                            Text("People, looks, occasions").foregroundStyle(Theme.mutedForeground))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .foregroundStyle(Theme.ink)
            }
            .font(Theme.body)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .stroke(Theme.controlBorder, lineWidth: 1))
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
