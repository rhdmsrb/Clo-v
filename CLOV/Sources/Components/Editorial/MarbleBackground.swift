import SwiftUI

/// Pale marble canvas: the app background with a few faint, seeded veins and a fine
/// paper grain. Fixed seed, so it never shimmers between renders. In dark mode the
/// veins are a soft light gray and the grain is skipped.
struct MarbleBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private static let seed: UInt64 = 0xC10F_5EED
    private static let veinCount = 14
    private static let branchesPerVein = 3
    private static let speckleCount = 700

    var body: some View {
        Theme.background
            .overlay {
                Canvas { context, size in
                    var rng = SeededRandom(seed: Self.seed)
                    let isDark = colorScheme == .dark
                    let veinColor = isDark ? Color.white : Color.black
                    for _ in 0..<Self.veinCount {
                        let width = 1.2 + rng.next() * 2.4
                        let opacity = (isDark ? 0.03 : 0.045) + rng.next() * 0.05
                        let path = Self.vein(in: size, rng: &rng)
                        context.stroke(path, with: .color(veinColor.opacity(opacity)), lineWidth: width)
                        for _ in 0..<Self.branchesPerVein {
                            let branch = Self.vein(in: size, rng: &rng, scale: 0.35)
                            context.stroke(branch, with: .color(veinColor.opacity(opacity * 0.6)), lineWidth: width * 0.5)
                        }
                    }
                    guard !isDark else { return }
                    for _ in 0..<Self.speckleCount {
                        let rect = CGRect(x: rng.next() * size.width, y: rng.next() * size.height,
                                          width: 0.6 + rng.next(), height: 0.6 + rng.next())
                        context.fill(Path(rect), with: .color(.black.opacity(0.03)))
                    }
                }
                .blur(radius: 1.6)
                .drawingGroup()
                .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
    }

    /// A wandering crack: a cubic curve from a random edge point across part of the canvas.
    private static func vein(in size: CGSize, rng: inout SeededRandom, scale: CGFloat = 1) -> Path {
        let start = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height)
        let span = max(size.width, size.height) * scale
        func point() -> CGPoint {
            CGPoint(x: start.x + (rng.next() - 0.3) * span, y: start.y + (rng.next() - 0.3) * span)
        }
        var path = Path()
        path.move(to: start)
        path.addCurve(to: point(), control1: point(), control2: point())
        return path
    }
}

/// Small deterministic generator (SplitMix64) for textures that must not change between renders.
struct SeededRandom {
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

#Preview("Marble") {
    MarbleBackground().ignoresSafeArea()
}
