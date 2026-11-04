import SwiftUI
import UIKit

// Visual direction: "Soft Pop Editorial" - blush-white surfaces, deep plum
// ink, dusty rose accent with a mint secondary, big radii, soft shadows.
enum Theme {
    // MARK: Palette
    // Rose #E491A6 is a fill/accent only (never text on light surfaces).
    // Use `accentDeep` for rose-family text/icons (>= 4.5:1 on background,
    // card and accentTint), and `accentForeground` (dark plum) on rose fills.
    static let accent = themed(.accent, 0xE491A6, 0xE491A6)
    /// Rose-family text/icon/stroke color: #72455A on light (7.2:1 on background), #F2B0C2 on dark.
    static let accentDeep = themed(.accentDeep, 0x72455A, 0xF2B0C2)
    /// Same value as `accentDeep`; kept so existing call sites keep working.
    static let accentSecondary = accentDeep
    /// Soft rose wash for selected chips / selected tab: #FBE3EA / #4A2A36.
    static let accentTint = themed(.accentTint, 0xFBE3EA, 0x4A2A36)
    /// Positive / success (mint family): #1B7F5C (4.6:1 on background) / #7FE0B8.
    static let win = adaptive(hex: 0x1B7F5C, 0x7FE0B8)

    // Small expressive icon colors; each keeps >= 3:1 against `background`.
    static let iconCoral = accentDeep
    static let iconApricot = adaptive(hex: 0x9A5642, 0xF0B59A)
    static let iconPlum = adaptive(hex: 0x845763, 0xD9A0B5)
    static let iconSage = adaptive(hex: 0x2A8F6C, 0x7FE0B8)
    /// Text/icons on top of `accent` (rose) fills: dark plum in both modes (6.6:1).
    static let accentForeground = themed(.accentForeground, 0x3A1A26, 0x3A1A26)

    static let background = themed(.background, 0xFCF6F8, 0x1D1216)
    static let card = themed(.card, 0xFFFFFF, 0x2A1A21)
    /// Surface for floating things (tab bar, sheets, popovers).
    static let cardElevated = themed(.cardElevated, 0xFFFFFF, 0x35222B)
    static let muted = themed(.muted, 0xF5EBEE, 0x3A2830)
    static let mutedForeground = themed(.mutedForeground, 0x6E555E, 0xCDB4BC)
    static let line = adaptive(hex: 0x3A2029, 0xF8EEF1)
    static let ink = themed(.ink, 0x3A2029, 0xF8EEF1)
    static let inverseText = adaptive(hex: 0xFFFFFF, 0x1D1216)

    /// Destructive / error text and icons; adapts for contrast in dark mode.
    static let danger = adaptive((0.75, 0.15, 0.13), (1.0, 0.45, 0.42))
    /// Solid primary fill (mauve light / rose dark). Prefer `heroGradient` for CTAs.
    static let primaryButtonFill = themed(.primaryButtonFill, 0x845763, 0xE491A6)
    /// Text on `primaryButtonFill` (6.0:1 light, 6.6:1 dark).
    static let primaryButtonText = adaptive(hex: 0xFFFFFF, 0x3A1A26)
    /// Legacy opaque tab bar surface.
    static let tabBarSurface = adaptive(hex: 0x3A2029, 0x2A1A21)

    /// Hero fill: deep plum -> mauve -> deep rose at 135deg (light); darker in dark mode.
    /// White text on every stop is >= 4.5:1.
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                themed(.heroStart, 0x4A2634, 0x2A1620),
                themed(.heroMid, 0x845763, 0x4A2634),
                themed(.heroEnd, 0xA04E6B, 0x6B3A52)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Radii
    static let cardRadius: CGFloat = 24
    static let tileRadius: CGFloat = 20
    static let smallRadius: CGFloat = 14
    static let controlRadius: CGFloat = 16
    static let fieldRadius: CGFloat = 16
    static let barRadius: CGFloat = 999
    static let chipRadius: CGFloat = 999
    static let avatarRadius: CGFloat = 999

    // MARK: Type
    // One typeface, Open Sans (OFL), for UI and display text. Every font is
    // Dynamic Type relative. Open Sans ships no static Medium, so .medium uses
    // Regular and .semibold uses SemiBold. Falls back to the system font if the
    // files are missing from the bundle.
    static let micro = font(.caption2, weight: .semibold)
    static let microMedium = font(.caption2, weight: .medium)
    static let caption = font(.caption, weight: .semibold)
    static let label = font(.footnote, weight: .semibold)
    static let bodyEmphasis = font(.subheadline, weight: .semibold)
    static let body = font(.body)
    static let headline = font(.headline, weight: .semibold)
    static let title = font(.title3, weight: .bold)

    /// Open Sans Bold display face (30pt, relative to title2). Display text only (>= 28pt):
    /// cap with `.dynamicTypeSize(...accessibility1)`, a line limit, and minimumScaleFactor >= 0.7.
    static var displayFont: Font { editorialFont(size: 30, relativeTo: .title2) }

    /// Display headings are authored at Bodoni sizes; Open Sans Bold needs less.
    private static let displayScale: CGFloat = 0.85

    static func editorialFont(size: CGFloat, relativeTo textStyle: Font.TextStyle = .largeTitle) -> Font {
        .custom(faceName(for: .bold), size: size * displayScale, relativeTo: textStyle)
    }

    /// Open Sans at the default size of a text style, scaling with Dynamic Type.
    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .custom(faceName(for: weight), size: defaultPointSize(for: style), relativeTo: style)
    }

    private static func faceName(for weight: Font.Weight) -> String {
        switch weight {
        case .heavy, .black: return "OpenSans-ExtraBold"
        case .bold: return "OpenSans-Bold"
        case .semibold: return "OpenSans-SemiBold"
        default: return "OpenSans-Regular"
        }
    }

    /// Open Sans reads larger than SF at the same point size, so every style
    /// sits one step below the system default (body 17 -> 15).
    private static func defaultPointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 30
        case .title: return 25
        case .title2: return 20
        case .title3: return 18
        case .headline: return 15
        case .body: return 15
        case .callout: return 14
        case .subheadline: return 13
        case .footnote: return 12
        case .caption: return 11
        case .caption2: return 10
        @unknown default: return 15
        }
    }

    // MARK: Shadows & motion
    static let cardShadow = Color.black.opacity(0.06)
    static let navyShadow = adaptiveAlpha((0.227, 0.125, 0.161), (0, 0, 0), alpha: 0.08)
    static let navyShadowStrong = adaptiveAlpha((0.227, 0.125, 0.161), (0, 0, 0), alpha: 0.18)

    /// Named springs. Always apply through `Theme.animation(_:reduceMotion:)` or `motionSafeAnimation`.
    static let press = Animation.spring(response: 0.24, dampingFraction: 0.82)
    static let snap = Animation.snappy(duration: 0.28)
    /// Quick feedback for chip and segment selection.
    static let quick = Animation.snappy(duration: 0.16)
    static let bounce = Animation.spring(response: 0.45, dampingFraction: 0.6)
    static let hero = Animation.spring(response: 0.55, dampingFraction: 0.85)
    static let settle = Animation.smooth(duration: 0.4)

    /// Minimum comfortable tap target.
    static let minTapSize: CGFloat = 44
    /// Border for unselected chips and text fields; ~3:1 against light and dark surfaces.
    static let controlBorder = line.opacity(0.55)

    /// Returns `animation`, or nil when Reduce Motion is on. Use with `withAnimation`.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    static var photoScrim: LinearGradient {
        LinearGradient(
            colors: [.clear, .black.opacity(0.55)],
            startPoint: .center,
            endPoint: .bottom
        )
    }

    // MARK: Color builders
    /// Palette-aware color: the default Rose palette uses the hand-tuned hex
    /// pair; any other palette generates the role from its hue. Re-resolves
    /// live when the palette trait changes.
    static func themed(_ role: PaletteRole, _ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            let id = trait[PaletteTrait.self]
            if id == ThemePalette.rose.id { return uiColor(hex: isDark ? dark : light) }
            return ThemePalette.resolve(id).color(role, dark: isDark)
        })
    }

    static func adaptive(hex light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            uiColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// RGB tuples in 0...1, resolved live from the system appearance.
    private static func adaptive(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> Color {
        adaptiveAlpha(light, dark, alpha: 1)
    }

    private static func adaptiveAlpha(_ light: (Double, Double, Double), _ dark: (Double, Double, Double), alpha: Double) -> Color {
        Color(UIColor { trait in
            let rgb = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
        })
    }
}

// MARK: - Elevation

/// Two-layer resting shadow: tight contact (black 6%, r1 y1) + soft navy ambient (8%, r18 y8).
struct LayeredShadow: ViewModifier {
    var tint: Color = Theme.cardShadow
    func body(content: Content) -> some View {
        content
            .shadow(color: tint, radius: 1, y: 1)
            .shadow(color: Theme.navyShadow, radius: 18, y: 8)
    }
}

/// Stronger shadow for floating things (tab bar, floating buttons).
struct ElevatedShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            .shadow(color: Theme.navyShadowStrong, radius: 24, y: 12)
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

/// Shared card surface: continuous large corners, no border, soft shadow.
struct SoftCard: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .layeredShadow()
    }
}

/// Raised card surface (`cardElevated`) with the floating shadow.
struct ElevatedCard: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.cardElevated, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .elevatedShadow()
    }
}

extension View {
    func softCard(radius: CGFloat = Theme.cardRadius, padding: CGFloat = 16) -> some View {
        modifier(SoftCard(radius: radius, padding: padding))
    }

    func elevatedCard(radius: CGFloat = Theme.cardRadius, padding: CGFloat = 16) -> some View {
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
