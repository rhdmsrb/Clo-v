import SwiftUI

/// The primary CTA: a black pill with white text (inverted in dark mode).
/// Use one per screen, placed low in the thumb zone.
struct PrimaryPillButton: View {
    let title: String
    var systemImage: String? = nil
    /// Stretch to the container width (default) or hug the label.
    var fillsWidth = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).lineLimit(1)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .fixedSize(horizontal: !fillsWidth, vertical: false)
    }
}

#Preview("Primary pill") {
    VStack(spacing: Spacing.m) {
        PrimaryPillButton(title: "Post a Fit-Check", systemImage: "plus") {}
        PrimaryPillButton(title: "Vote now", fillsWidth: false) {}
        Button("Secondary") {}.buttonStyle(OutlineButtonStyle())
    }
    .padding(Spacing.m)
    .background(Theme.background)
}
