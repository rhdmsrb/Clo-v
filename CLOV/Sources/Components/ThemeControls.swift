import SwiftUI

/// Capsule CTA: hero gradient fill, >= 52pt tall, press scale 0.96, soft haptic.
struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false
    private static let minHeight: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .frame(maxWidth: .infinity, minHeight: Self.minHeight)
            .padding(.horizontal, 20)
            .foregroundStyle(isDisabled ? AnyShapeStyle(Theme.mutedForeground) : AnyShapeStyle(Color.white))
            .background(fill, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .motionSafeAnimation(value: configuration.isPressed)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: configuration.isPressed) { _, pressed in
                pressed && !isDisabled
            }
    }

    private var fill: AnyShapeStyle {
        isDisabled ? AnyShapeStyle(Theme.muted) : AnyShapeStyle(Theme.heroGradient)
    }
}

/// Secondary capsule: opaque card fill with a faint outline (no blur under text).
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 20)
            .background(configuration.isPressed ? Theme.muted : Theme.cardElevated, in: Capsule(style: .continuous))
            .foregroundStyle(Theme.ink)
            .overlay(Capsule(style: .continuous).stroke(Theme.controlBorder, lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .motionSafeAnimation(value: configuration.isPressed)
    }
}

/// Circular avatar with an optional pink ring.
struct AvatarView: View {
    let url: String?
    let nickname: String?
    var size: CGFloat = 40
    var ringed: Bool = false

    private static let ringWidth: CGFloat = 2.5
    private static let ringGap: CGFloat = 3

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
        .clipShape(Circle())
        .overlay {
            if ringed {
                Circle()
                    .stroke(Theme.accent, lineWidth: Self.ringWidth)
                    .padding(-Self.ringGap - Self.ringWidth / 2)
            }
        }
        .accessibilityHidden(true)
    }

    private var initialCircle: some View {
        Circle()
            .fill(Theme.heroGradient)
            .overlay(
                Text(String((nickname?.first).map(String.init) ?? "?").uppercased())
                    .font(Theme.editorialFont(size: size * 0.4, relativeTo: .body))
                    .foregroundStyle(Color.white)
            )
    }
}

/// Shared chip look: selected = accentTint fill + accentDeep stroke/text (+ checkmark when
/// Differentiate Without Color is on); unselected = muted fill with a control border.
private struct ChipSurface: ViewModifier {
    let isSelected: Bool
    var unselectedFill: Color = Theme.muted
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
        let selectedWidth: CGFloat = contrast == .increased ? 2.5 : 1.5
        content
            .background(isSelected ? Theme.accentTint : unselectedFill, in: shape)
            .overlay(shape.stroke(isSelected ? Theme.accentDeep : Theme.controlBorder,
                                  lineWidth: isSelected ? selectedWidth : 1))
            .contentShape(shape)
    }
}

private struct ChipLabel<Label: View>: View {
    let isSelected: Bool
    @ViewBuilder var label: () -> Label
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        HStack(spacing: 6) {
            if isSelected && differentiate {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).accessibilityHidden(true)
            }
            label()
        }
    }
}

struct ChipToggle: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipLabel(isSelected: selected) { Text(label) }
                .font(Theme.label)
                .foregroundStyle(selected ? Theme.accentDeep : Theme.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(minHeight: Theme.minTapSize)
                .modifier(ChipSurface(isSelected: selected))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .motionSafeAnimation(Theme.snap, value: selected)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Toggle chip whose padding, minimum height, background and hit
/// shape all live inside the button label, so the whole chip is tappable.
struct ChipButtonStyle: ButtonStyle {
    var isSelected: Bool
    var font: Font = Theme.caption
    var expands = false
    var unselectedFill: Color = Theme.muted
    var unselectedForeground: Color = Theme.ink
    var horizontalPadding: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        ChipLabel(isSelected: isSelected) { configuration.label }
            .font(font)
            .foregroundStyle(isSelected ? Theme.accentDeep : unselectedForeground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: Theme.minTapSize)
            .modifier(ChipSurface(isSelected: isSelected, unselectedFill: unselectedFill))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
