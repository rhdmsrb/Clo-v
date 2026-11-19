import SwiftUI

/// Small label for a style tag ("streetwear", "y2k"). Not interactive.
struct StyleTag: View {
    let text: String
    var style: Style = .onSurface

    enum Style { case onPhoto, onSurface }

    var body: some View {
        Text(text)
            .font(Theme.font(.caption, weight: .medium))
            .foregroundStyle(style == .onPhoto ? Color.white : Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(background, in: Capsule(style: .continuous))
            .overlay {
                if style == .onPhoto {
                    Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                }
            }
    }

    private var background: Color {
        style == .onPhoto ? Color.white.opacity(0.18) : Theme.muted
    }
}

/// A row of tags that wraps instead of truncating. VoiceOver reads it as one list.
struct StyleTagRow: View {
    let tags: [String]
    var style: StyleTag.Style = .onSurface

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: Spacing.xs + 2) {
                ForEach(tags, id: \.self) { StyleTag(text: $0, style: style) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tags: \(tags.joined(separator: ", "))")
        }
    }
}

#Preview("Style tags") {
    VStack(alignment: .leading, spacing: Spacing.m) {
        StyleTagRow(tags: ["#streetwear", "#y2k", "#campus"])
        StyleTagRow(tags: ["#minimal", "#date night"], style: .onPhoto)
            .padding(Spacing.m)
            .background(Color.black.opacity(0.7))
    }
    .padding(Spacing.m)
    .background(Theme.background)
}
