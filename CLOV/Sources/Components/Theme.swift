import SwiftUI
import UIKit

// Visual direction: clean white surfaces, ink, and a restrained champagne accent.
enum Theme {
    static let accent = adaptive((0.40, 0.28, 0.17), (0.86, 0.74, 0.56))
    static let accentSecondary = adaptive((0.61, 0.43, 0.28), (0.75, 0.61, 0.42))
    // Small, expressive icon colors add personality without changing the
    // neutral typography or the black-and-white surfaces.
    static let iconCoral = Color(red: 0.82, green: 0.31, blue: 0.29)
    static let iconApricot = Color(red: 0.91, green: 0.55, blue: 0.25)
    static let iconPlum = Color(red: 0.49, green: 0.34, blue: 0.57)
    static let iconSage = Color(red: 0.34, green: 0.51, blue: 0.40)
    static let accentForeground = Color.white
    static let background = adaptive((1.0, 1.0, 1.0), (0.06, 0.06, 0.06))
    static let card = adaptive((1.0, 1.0, 1.0), (0.12, 0.12, 0.12))
    static let muted = adaptive((0.96, 0.96, 0.96), (0.18, 0.18, 0.18))
    static let mutedForeground = adaptive((0.38, 0.38, 0.38), (0.74, 0.74, 0.74))
    static let line = adaptive((0.0, 0.0, 0.0), (1.0, 1.0, 1.0))
    static let ink = adaptive((0.02, 0.02, 0.02), (0.98, 0.98, 0.98))
    static let inverseText = adaptive((1.0, 1.0, 1.0), (0.02, 0.02, 0.02))

    static let cardRadius: CGFloat = 16
    static let tileRadius: CGFloat = 16

    static var displayFont: Font { editorialFont(size: 30, relativeTo: .title2) }

    static func editorialFont(size: CGFloat, relativeTo textStyle: Font.TextStyle = .largeTitle) -> Font {
        .custom("BodoniSvtyTwoITCTT-Book", size: size, relativeTo: textStyle)
    }

    static let cardShadow = Color.black.opacity(0.045)
    static let press = Animation.spring(response: 0.24, dampingFraction: 0.82)

    // Kept for existing views. The accent is intentionally flat so photos and
    // typography remain the visual focus.
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accent],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static var glossHighlight: LinearGradient {
        LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom)
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
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Theme.line.opacity(0.12), lineWidth: 1))
            .shadow(color: Theme.cardShadow, radius: 5, y: 2)
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
            .background(isDisabled ? Theme.muted : Theme.ink)
            .foregroundStyle(Theme.inverseText)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
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
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.line.opacity(0.35), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
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
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialCircle
                }
            } else {
                initialCircle
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if ringed {
                Circle().stroke(Theme.accentGradient, lineWidth: 2.5)
                    .padding(-3)
                    .shadow(color: Theme.accent.opacity(0.45), radius: 6)
            }
        }
    }

    private var initialCircle: some View {
        Circle()
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
                .background(selected ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.card))
                .foregroundStyle(selected ? Theme.inverseText : Color.primary)
                .clipShape(Capsule())
                .overlay(Capsule()
                    .stroke(Theme.line.opacity(selected ? 0 : 0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(Theme.press, value: selected)
        .sensoryFeedback(.selection, trigger: selected)
    }
}
