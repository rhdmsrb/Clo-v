import SwiftUI
import UIKit

// Visual direction: white surfaces, deep blue ink, and a bubblegum pink accent.
enum Theme {
    // Palette: deep blue #0A2472, pure white, bubblegum pink #FF9ECF.
    // Pink is a fill/accent color (about 1.9:1 on white). Text and icons on light
    // surfaces use `accentSecondary` or `ink`; on dark or photo surfaces pink is fine.
    static let accent = adaptive((1.0, 0.62, 0.81), (1.0, 0.62, 0.81))
    /// Blue (light) / soft pink (dark) for text, icons and strokes on page surfaces.
    static let accentSecondary = adaptive((0.106, 0.227, 0.620), (1.0, 0.72, 0.86))
    // Small, expressive icon colors for page surfaces; each keeps >= 3:1
    // against `background` in both modes.
    static let iconCoral = adaptive((0.78, 0.13, 0.46), (1.0, 0.62, 0.81))
    static let iconApricot = adaptive((0.106, 0.227, 0.620), (0.725, 0.776, 0.941))
    static let iconPlum = adaptive((0.20, 0.31, 0.66), (0.62, 0.70, 1.0))
    static let iconSage = adaptive((0.12, 0.42, 0.80), (0.55, 0.75, 1.0))
    /// Text/icons on top of `accent` (pink) fills: deep blue in both modes.
    static let accentForeground = adaptive((0.039, 0.141, 0.447), (0.039, 0.141, 0.447))
    static let background = adaptive((1.0, 1.0, 1.0), (0.024, 0.090, 0.302))
    static let card = adaptive((1.0, 1.0, 1.0), (0.043, 0.129, 0.439))
    static let muted = adaptive((0.957, 0.961, 0.969), (0.063, 0.165, 0.478))
    static let mutedForeground = adaptive((0.290, 0.353, 0.561), (0.725, 0.776, 0.941))
    static let line = adaptive((0.039, 0.141, 0.447), (1.0, 1.0, 1.0))
    static let ink = adaptive((0.039, 0.141, 0.447), (1.0, 1.0, 1.0))
    static let inverseText = adaptive((1.0, 1.0, 1.0), (0.024, 0.090, 0.302))

    /// Destructive / error text and icons; adapts for contrast in dark mode.
    static let danger = adaptive((0.75, 0.15, 0.13), (1.0, 0.45, 0.42))
    /// Primary button fill: deep blue in light mode, pink in dark mode.
    static let primaryButtonFill = adaptive((0.039, 0.141, 0.447), (1.0, 0.62, 0.81))
    /// Text on `primaryButtonFill`.
    static let primaryButtonText = adaptive((1.0, 1.0, 1.0), (0.039, 0.141, 0.447))
    /// Floating tab bar surface (deep blue in light mode, lifted in dark mode so it stays visible).
    static let tabBarSurface = adaptiveAlpha((0.039, 0.141, 0.447), (0.043, 0.129, 0.439), alpha: 1.0)

    // Corner-radius tokens. The visual direction is square-cornered and
    // editorial; raise these here (not per view) if a softer look is wanted.
    static let cardRadius: CGFloat = 0
    static let tileRadius: CGFloat = 0
    static let smallRadius: CGFloat = 0
    static let controlRadius: CGFloat = 0
    static let fieldRadius: CGFloat = 0
    static let barRadius: CGFloat = 0
    static let chipRadius: CGFloat = 0
    static let avatarRadius: CGFloat = 0

    // Dynamic Type text styles. Prefer these over fixed `.system(size:)`.
    static let micro = Font.system(.caption2, design: .default, weight: .black)
    static let microMedium = Font.system(.caption2, design: .default, weight: .bold)
    static let caption = Font.system(.caption, design: .default, weight: .semibold)
    static let label = Font.system(.footnote, design: .default, weight: .bold)
    static let bodyEmphasis = Font.system(.subheadline, design: .default, weight: .semibold)

    static var displayFont: Font { editorialFont(size: 30, relativeTo: .title2) }

    static func editorialFont(size: CGFloat, relativeTo textStyle: Font.TextStyle = .largeTitle) -> Font {
        .custom("BodoniSvtyTwoITCTT-Book", size: size, relativeTo: textStyle)
    }

    static let cardShadow = Color.black.opacity(0.045)
    static let press = Animation.spring(response: 0.24, dampingFraction: 0.82)

    /// Minimum comfortable tap target.
    static let minTapSize: CGFloat = 44
    /// Border for unselected chips and text fields; >= 3:1 against light and dark surfaces.
    static let controlBorder = line.opacity(0.55)

    /// Returns `animation`, or nil when Reduce Motion is on. Use with `withAnimation`.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Builds a `Color` that resolves to `light` or `dark` RGB (0...1,
    /// each a 3-tuple) depending on the system appearance, re-evaluated
    /// live rather than fixed at first use.
    private static func adaptive(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> Color {
        Color(UIColor { trait in
            let rgb = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    private static func adaptiveAlpha(_ light: (Double, Double, Double), _ dark: (Double, Double, Double), alpha: Double) -> Color {
        Color(UIColor { trait in
            let rgb = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
        })
    }

    static var photoScrim: LinearGradient {
        LinearGradient(
            colors: [.clear, .black.opacity(0.55)],
            startPoint: .center,
            endPoint: .bottom
        )
    }
}

/// Editorial surfaces use a small contact shadow only; borders define the
/// hierarchy more clearly than floating cards.
struct LayeredShadow: ViewModifier {
    var tint: Color = Theme.cardShadow
    func body(content: Content) -> some View {
        content
            .shadow(color: tint, radius: 2, y: 2)
    }
}

extension View {
    func layeredShadow(_ tint: Color = Theme.cardShadow) -> some View {
        modifier(LayeredShadow(tint: tint))
    }
}

/// Shared card surface with modest corners and a quiet border.
struct SoftCard: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .stroke(Theme.line.opacity(0.18), lineWidth: 1))
    }
}

extension View {
    func softCard(radius: CGFloat = Theme.cardRadius, padding: CGFloat = 16) -> some View {
        modifier(SoftCard(radius: radius, padding: padding))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .default).weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(isDisabled ? Theme.muted : Theme.primaryButtonFill)
            .foregroundStyle(isDisabled ? Theme.mutedForeground : Theme.primaryButtonText)
            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .motionSafeAnimation(value: configuration.isPressed)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .default).weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(configuration.isPressed ? Theme.muted : Theme.card)
            .foregroundStyle(Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius)
                .stroke(Theme.controlBorder, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .motionSafeAnimation(value: configuration.isPressed)
    }
}

struct AvatarView: View {
    let url: String?
    let nickname: String?
    var size: CGFloat = 40
    var ringed: Bool = false

    var body: some View {
        Group {
            if let url, let imageURL = URL(string: url) {
                CachedImage(url: imageURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initialCircle
                    }
                }
            } else {
                initialCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.avatarRadius))
        .overlay {
            if ringed {
                RoundedRectangle(cornerRadius: Theme.avatarRadius)
                    .stroke(Theme.accentSecondary, lineWidth: 1.5)
                    .padding(-3)
            }
        }
        .accessibilityHidden(true)
    }

    private var initialCircle: some View {
        RoundedRectangle(cornerRadius: Theme.avatarRadius)
            .fill(Theme.ink)
            .overlay(
                Text(String((nickname?.first).map(String.init) ?? "?").uppercased())
                    .font(.system(size: size * 0.4, weight: .bold, design: .default))
                    .foregroundStyle(Theme.inverseText)
            )
    }
}

struct ChipToggle: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(.footnote, design: .default).weight(.bold))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(minHeight: Theme.minTapSize)
                .background(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.card))
                .foregroundStyle(selected ? Theme.inverseText : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius)
                    .stroke(selected ? Color.clear : Theme.controlBorder, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: Theme.chipRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .motionSafeAnimation(value: selected)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

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

/// Toggle chip whose padding, minimum height, background and hit
/// shape all live inside the button label, so the whole chip is tappable.
struct ChipButtonStyle: ButtonStyle {
    var isSelected: Bool
    var font: Font = Theme.caption
    var expands = false
    var unselectedFill: Color = Theme.muted
    var unselectedForeground: Color = .primary
    var horizontalPadding: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(isSelected ? Theme.accentForeground : unselectedForeground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: Theme.minTapSize)
            .background(isSelected ? Theme.accent : unselectedFill, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius).stroke(isSelected ? Theme.accentSecondary : Theme.controlBorder, lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.chipRadius))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
