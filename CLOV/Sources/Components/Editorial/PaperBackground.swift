import SwiftUI

/// Canvas color with a very faint paper grain, for editorial headers. The grain is
/// a fixed, seeded speckle (same on every launch) and is skipped in dark mode,
/// where it would read as noise.
struct PaperBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private static let speckleCount = 900
    private static let speckleOpacity = 0.035
    private static let seed: UInt64 = 0xC10F

    var body: some View {
        Theme.background
            .overlay {
                if colorScheme == .light {
                    Canvas { context, size in
                        var rng = SeededRandom(seed: Self.seed)
                        for _ in 0..<Self.speckleCount {
                            let x = rng.next() * size.width
                            let y = rng.next() * size.height
                            let side = 0.6 + rng.next() * 1.2
                            context.fill(Path(CGRect(x: x, y: y, width: side, height: side)),
                                         with: .color(.black.opacity(Self.speckleOpacity)))
                        }
                    }
                    .drawingGroup()
                    .allowsHitTesting(false)
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview("Paper") {
    PaperBackground().frame(height: 240)
}
