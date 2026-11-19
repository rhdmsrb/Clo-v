import SwiftUI
import UIKit

// Visual direction ("Clay"): light gray canvas, white cards, near-black ink and
// one warm clay-orange accent. The hex pairs below are the Clay default; the
// original burgundy values live on as the "Classic" palette (ThemePalette+Classic).
extension Theme {
    // MARK: Accent
    /// Accent fill: the selected chip, the selected tab icon, progress bars.
    static let accent = themed(.accent, 0xE2552B, 0xFF7A4D)
    /// Accent text, icons and strokes on canvas and card surfaces (>= 4.5:1).
    static let accentDeep = themed(.accentDeep, 0xB43F1C, 0xFF9A75)
    /// Same value as `accentDeep`; kept so existing call sites keep working.
    static let accentSecondary = accentDeep
    /// Soft accent wash for highlighted rows and badges.
    static let accentTint = themed(.accentTint, 0xFCE9E2, 0x3A2219)
    /// Text and icons on accent fills.
    static let accentForeground = themed(.accentForeground, 0xFFFFFF, 0x1A0D08)
    /// Positive / success (mint family): #1B7F5C (4.6:1 on background) / #7FE0B8.
    static let win = adaptive(hex: 0x1B7F5C, 0x7FE0B8)

    // Small expressive icon colors; each keeps >= 3:1 against `background`.
    static let iconCoral = accentDeep
    static let iconApricot = adaptive(hex: 0x9A5642, 0xF0B59A)
    static let iconPlum = adaptive(hex: 0x6B5A7A, 0xC4B3D6)
    static let iconSage = adaptive(hex: 0x2A8F6C, 0x7FE0B8)

    // MARK: Surfaces and ink
    /// App canvas: soft light gray, so white cards read without shadows.
    static let background = themed(.background, 0xF1F2F4, 0x0E0F11)
    static let card = themed(.card, 0xFFFFFF, 0x1A1B1E)
    /// Surface for floating things (tab bar, floating buttons, sheets).
    static let cardElevated = themed(.cardElevated, 0xFFFFFF, 0x232428)
    /// Soft gray card and unselected-control fill.
    static let muted = themed(.muted, 0xE7E8EB, 0x26272B)
    static let mutedForeground = themed(.mutedForeground, 0x5F6168, 0xA6A8AE)
    static let ink = themed(.ink, 0x111214, 0xF4F4F5)
    /// Hairlines and outlines; same hue as `ink`, used at reduced opacity.
    static let line = ink
    static let inverseText = adaptive(hex: 0xFFFFFF, 0x0E0F11)

    /// Destructive / error text and icons; adapts for contrast in dark mode.
    static let danger = adaptive(hex: 0xBF2621, 0xFF736B)
    /// Primary CTA: a near-black pill with white text (inverted in dark mode).
    static let primaryButtonFill = themed(.primaryButtonFill, 0x111214, 0xF4F4F5)
    /// Text on `primaryButtonFill`.
    static let primaryButtonText = themed(.primaryButtonText, 0xFFFFFF, 0x111214)
    /// Legacy opaque tab bar surface.
    static let tabBarSurface = adaptive(hex: 0x111214, 0x1A1B1E)

    /// Dark hero fill: ink through graphite. White text on every stop is >= 4.5:1.
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                themed(.heroStart, 0x111214, 0x232428),
                themed(.heroMid, 0x24262A, 0x33353A),
                themed(.heroEnd, 0x3A3C42, 0x45474D)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Bottom gradient that keeps white text legible over a photo.
    static var photoScrim: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.45),
                .init(color: .black.opacity(0.35), location: 0.72),
                .init(color: .black.opacity(0.72), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: Color builders
    /// Palette-aware color: Clay uses the hex pair passed here, Classic uses its
    /// stored burgundy pair, and any generated palette derives the role from its
    /// hue. Re-resolves live when the palette trait changes.
    static func themed(_ role: PaletteRole, _ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            let palette = ThemePalette.resolve(trait[PaletteTrait.self])
            if palette == .clay { return uiColor(hex: isDark ? dark : light) }
            if palette == .classic, let pair = ThemePalette.classicHex[role] {
                return uiColor(hex: isDark ? pair.dark : pair.light)
            }
            return palette.color(role, dark: isDark)
        })
    }

    static func adaptive(hex light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            uiColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func uiColor(hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
