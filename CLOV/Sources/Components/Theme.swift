import SwiftUI
import UIKit

// Visual direction: editorial fashion publication.
// Strong ink-on-paper contrast, square-ish surfaces, one muted lavender
// accent, and photographs that carry more visual weight than app chrome.
enum Theme {
    static let accent = Color(red: 0.48, green: 0.45, blue: 0.65) // #7A73A6
    static let accentForeground = Color.white
    static let background = adaptive((0.95, 0.94, 0.90), (0.07, 0.07, 0.07))
    static let card = adaptive((0.985, 0.98, 0.95), (0.12, 0.12, 0.12))
    static let muted = adaptive((0.88, 0.86, 0.81), (0.19, 0.19, 0.19))
    static let mutedForeground = adaptive((0.31, 0.30, 0.28), (0.74, 0.73, 0.70))
    static let line = adaptive((0.08, 0.08, 0.08), (0.92, 0.91, 0.87))
    static let ink = adaptive((0.06, 0.06, 0.06), (0.94, 0.93, 0.89))
    static let inverseText = adaptive((0.98, 0.97, 0.94), (0.06, 0.06, 0.06))

    static let cardRadius: CGFloat = 12
    static let tileRadius: CGFloat = 10

    static var displayFont: Font { .system(.title2, design: .default).weight(.black) }

    static let cardShadow = Color.black.opacity(0.08)
    static let press = Animation.spring(response: 0.24, dampingFraction: 0.82)

    // Kept for existing views, but intentionally flat: this direction does
    // not use gloss or candy-like gradients.
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

/// The shared paper card: compact corners, visible rule, minimal elevation.
struct SoftCard: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Theme.line.opacity(0.22), lineWidth: 1))
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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.line.opacity(selected ? 0 : 0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(Theme.press, value: selected)
        .sensoryFeedback(.selection, trigger: selected)
    }
}
