import SwiftUI

/// An optional all-caps label above a rounded, card-wrapped form
/// control — the pattern that used to be copy-pasted with mismatched
/// paddings/radii across Auth (EMAIL/PASSWORD), Onboarding (NICKNAME),
/// Create (CAPTION/POST TO), and Groups (invite code, new-group name).
///
/// `insetStyle` swaps the elevated card+shadow look for a flatter fill
/// against `Theme.background` — for a field that already sits inside
/// another `.softCard()`, so two shadows don't stack.
struct LabeledField<Content: View>: View {
    var label: String? = nil
    var radius: CGFloat = 18
    var padding: CGFloat = 16
    var insetStyle: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                Text(label)
                    .font(.system(.caption2, design: .default).weight(.bold))
                    .foregroundStyle(.secondary)
            }
            content()
                .padding(padding)
                .background(insetStyle ? Theme.background : Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .layeredShadow(insetStyle ? .clear : Theme.cardShadow)
        }
    }
}
