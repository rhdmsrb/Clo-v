import SwiftUI

/// Results stay blurred until the viewer has voted, created the post, or voting ended.
enum BlurReveal {
    static let blurRadius: CGFloat = 22

    static func isRevealed(hasVoted: Bool, isCreator: Bool, ended: Bool) -> Bool {
        hasVoted || isCreator || ended
    }
}

private struct BlurRevealModifier: ViewModifier {
    let isRevealed: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: isRevealed ? 0 : BlurReveal.blurRadius)
            .allowsHitTesting(isRevealed)
            .accessibilityHidden(!isRevealed)
            .motionSafeAnimation(Theme.settle, value: isRevealed)
    }
}

extension View {
    func blurReveal(isRevealed: Bool) -> some View {
        modifier(BlurRevealModifier(isRevealed: isRevealed))
    }

    func blurReveal(hasVoted: Bool, isCreator: Bool, ended: Bool) -> some View {
        blurReveal(isRevealed: BlurReveal.isRevealed(hasVoted: hasVoted, isCreator: isCreator, ended: ended))
    }
}

#Preview("BlurReveal") {
    struct Host: View {
        @State var voted = false
        var body: some View {
            VStack {
                Text("62% / 38%").font(.largeTitle)
                    .blurReveal(hasVoted: voted, isCreator: false, ended: false)
                Button("Vote") { voted = true }
            }
        }
    }
    return Host()
}
