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

/// Small deterministic generator (SplitMix64) so the grain never shimmers between renders.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// Uniform value in 0..<1.
    mutating func next() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}

#Preview("Paper") {
    PaperBackground().frame(height: 240)
}
