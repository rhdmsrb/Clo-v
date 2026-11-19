import SwiftUI

/// Design tokens. Split by concern:
/// - `Theme+Colors.swift`: palette and color builders
/// - `Theme+Typography.swift`: type scale and `EditorialTitle`
/// - `Theme+Spacing.swift`: 8pt grid (`Spacing`)
/// - `Theme+Radius.swift`: corner radii (`Radius`)
/// This file holds elevation, motion and the shared card surfaces.
enum Theme {
    // MARK: Shadows
    static let cardShadow = Color.black.opacity(0.05)
    static let navyShadow = Color.black.opacity(0.08)
    static let navyShadowStrong = Color.black.opacity(0.14)

    // MARK: Motion
    /// Named springs. Always apply through `Theme.animation(_:reduceMotion:)` or `motionSafeAnimation`.
    static let press = Animation.spring(response: 0.24, dampingFraction: 0.82)
    static let snap = Animation.snappy(duration: 0.28)
    /// Quick feedback for chip and segment selection.
    static let quick = Animation.snappy(duration: 0.16)
    static let bounce = Animation.spring(response: 0.45, dampingFraction: 0.6)
    static let hero = Animation.spring(response: 0.55, dampingFraction: 0.85)
    static let settle = Animation.smooth(duration: 0.4)

    /// Border for unselected chips and text fields; ~3:1 against light and dark surfaces.
    static let controlBorder = line.opacity(0.22)

    /// Returns `animation`, or nil when Reduce Motion is on. Use with `withAnimation`.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Elevation

/// Resting shadow, kept very faint: cards sit flat on the gray canvas.
struct LayeredShadow: ViewModifier {
    var tint: Color = Theme.cardShadow
    func body(content: Content) -> some View {
        content.shadow(color: tint, radius: 1, y: 1)
    }
}

/// Soft shadow for floating things only (tab bar, floating icon buttons).
struct ElevatedShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            .shadow(color: Theme.navyShadowStrong, radius: 20, y: 8)
    }
}

extension View {
    func layeredShadow(_ tint: Color = Theme.cardShadow) -> some View {
        modifier(LayeredShadow(tint: tint))
    }

    func elevatedShadow() -> some View {
        modifier(ElevatedShadow())
    }
}

// MARK: - Cards

/// Shared card surface: white, continuous 24pt corners, no shadow.
struct SoftCard: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    var padding: CGFloat = Spacing.m
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Raised card surface (`cardElevated`) with the floating shadow.
struct ElevatedCard: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    var padding: CGFloat = Spacing.m
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.cardElevated, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .elevatedShadow()
    }
}

extension View {
    func softCard(radius: CGFloat = Theme.cardRadius, padding: CGFloat = Spacing.m) -> some View {
        modifier(SoftCard(radius: radius, padding: padding))
    }

    func elevatedCard(radius: CGFloat = Theme.cardRadius, padding: CGFloat = Spacing.m) -> some View {
        modifier(ElevatedCard(radius: radius, padding: padding))
    }
}

// MARK: - Motion

/// Applies `animation` only when Reduce Motion is off.
private struct MotionSafeAnimation<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(Theme.animation(animation, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    func motionSafeAnimation<Value: Equatable>(_ animation: Animation = Theme.press, value: Value) -> some View {
        modifier(MotionSafeAnimation(animation: animation, value: value))
    }
}
