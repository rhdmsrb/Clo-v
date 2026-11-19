import SwiftUI

/// Circular floating button (search, notifications): elevated surface with a soft
/// shadow and an optional count badge. 44pt, so it meets the minimum tap size.
struct FloatingIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var badgeCount: Int = 0
    var identifier: String? = nil
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = Theme.minTapSize
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 17
    private static let maxBadge = 99

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .background(Theme.cardElevated, in: Circle())
                .elevatedShadow()
                .overlay(alignment: .topTrailing) { badge }
                .contentShape(Circle())
        }
        .buttonStyle(FloatingPressStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(badgeCount > 0 ? "\(badgeCount) unread" : "")
        .modifier(OptionalAccessibilityIdentifier(identifier: identifier))
    }

    @ViewBuilder
    private var badge: some View {
        if badgeCount > 0 {
            Text(badgeCount > Self.maxBadge ? "\(Self.maxBadge)+" : "\(badgeCount)")
                .font(Theme.font(.caption2, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.accentForeground)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Theme.accent, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.cardElevated, lineWidth: 2))
                .offset(x: 4, y: -4)
                .accessibilityHidden(true)
        }
    }
}

private struct FloatingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .motionSafeAnimation(Theme.press, value: configuration.isPressed)
    }
}

struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

#Preview("Floating icon buttons") {
    HStack(spacing: Spacing.s) {
        FloatingIconButton(systemImage: "magnifyingglass", accessibilityLabel: "Search") {}
        FloatingIconButton(systemImage: "bell", accessibilityLabel: "Notifications", badgeCount: 3) {}
    }
    .padding(Spacing.l)
    .background(Theme.background)
}
