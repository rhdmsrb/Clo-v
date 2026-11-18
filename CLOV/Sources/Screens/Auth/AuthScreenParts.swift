import SwiftUI
import UIKit

/// The photo behind the auth screens. Uses the `AuthHero` image when the asset
/// catalog has one; otherwise a warm, soft studio backdrop so the screen still
/// reads as a fashion cover.
struct AuthHeroPhoto: View {
    /// Name of the optional asset-catalog image for the auth cover.
    static let assetName = "AuthHero"
    /// Which part of the photo stays in view when it is cropped (`.top` keeps the face
    /// in the short band above the login form).
    var alignment: Alignment = .center

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let photo = UIImage(named: Self.assetName) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    fallback
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: alignment)
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        LinearGradient(colors: [Color(red: 0.94, green: 0.90, blue: 0.85),
                                Color(red: 0.84, green: 0.76, blue: 0.67)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .bottomTrailing) {
                // Soft window light falling across the backdrop.
                Ellipse()
                    .fill(.white.opacity(0.35))
                    .frame(width: 420, height: 260)
                    .rotationEffect(.degrees(-28))
                    .offset(x: 120, y: -140)
                    .blur(radius: 40)
            }
            .overlay {
                Image(systemName: "figure.stand.dress")
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 90)
                    .padding(.vertical, 60)
                    .foregroundStyle(Color(red: 0.55, green: 0.45, blue: 0.36).opacity(0.35))
            }
    }
}

/// The CLO·V wordmark set over the auth photo.
struct AuthWordmark: View {
    var tagline: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CLO·V")
                .font(Theme.editorialFont(size: 34, weight: .bold))
                .kerning(-0.5)
            if let tagline {
                Text(tagline)
                    .font(Theme.font(.caption, weight: .medium))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(Color.white)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Rounded input row: leading icon, the field, and an optional trailing control
/// (the password's show/hide eye).
struct AuthInputRow<Field: View, Trailing: View>: View {
    let systemImage: String
    var isFocused = false
    var errorMessage: String? = nil
    @ViewBuilder let field: () -> Field
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                field()
                    .font(Theme.body)
                trailing()
            }
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: Theme.minTapSize + 6)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 1.5 : 1)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.danger)
            }
        }
    }

    private var borderColor: Color {
        if errorMessage != nil { return Theme.danger }
        return isFocused ? Theme.ink : Theme.controlBorder
    }
}

extension AuthInputRow where Trailing == EmptyView {
    init(systemImage: String, isFocused: Bool = false, errorMessage: String? = nil,
         @ViewBuilder field: @escaping () -> Field) {
        self.init(systemImage: systemImage, isFocused: isFocused, errorMessage: errorMessage,
                  field: field, trailing: { EmptyView() })
    }
}

/// Light pill over the photo ("Log in") or a frosted one ("Sign up").
struct AuthCoverButtonStyle: ButtonStyle {
    var isFrosted = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(.headline, weight: .semibold))
            .foregroundStyle(isFrosted ? Color.white : Color.black)
            .frame(maxWidth: .infinity, minHeight: Theme.ctaHeight)
            .background {
                if isFrosted {
                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.5), lineWidth: 1))
                } else {
                    Capsule(style: .continuous).fill(.white.opacity(0.92))
                }
            }
            .environment(\.colorScheme, .dark)
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .motionSafeAnimation(value: configuration.isPressed)
    }
}

#Preview("Auth parts") {
    VStack(spacing: Spacing.m) {
        ZStack(alignment: .topLeading) {
            AuthHeroPhoto().frame(height: 220)
            AuthWordmark(tagline: "Your look, your circle").padding(Spacing.l)
        }
        AuthInputRow(systemImage: "envelope") { TextField("Email address", text: .constant("")) }
            .padding(.horizontal, Spacing.l)
        AuthInputRow(systemImage: "lock", errorMessage: "Use at least 6 characters.") {
            SecureField("Password", text: .constant("123"))
        } trailing: {
            Image(systemName: "eye")
        }
        .padding(.horizontal, Spacing.l)
    }
    .background(Theme.card)
}
