import SwiftUI

/// A percentage that counts up smoothly instead of jumping. Animate `value`
/// with `withAnimation` and SwiftUI interpolates every frame in between.
struct CountingPercentText: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))%")
    }
}

/// A short burst of confetti for backing the winning look. Particles follow a
/// fixed recipe (no randomness), so it looks the same every time and costs one
/// Canvas redraw per frame. Callers should skip it when Reduce Motion is on.
struct ConfettiBurst: View {
    static let duration: TimeInterval = 1.8

    private static let particleCount = 44
    private static let gravity: Double = 720
    private static let fadeStart: Double = 1.2
    private static let palette: [Color] = [Theme.accent, Theme.accentDeep, Theme.win, Theme.iconApricot, Theme.iconPlum]

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let elapsed = context.date.timeIntervalSince(start)
                guard elapsed < Self.duration else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.6)
                let fade = 1 - max(0, (elapsed - Self.fadeStart) / (Self.duration - Self.fadeStart))
                for index in 0..<Self.particleCount {
                    draw(index, at: elapsed, from: origin, fade: fade, on: &canvas)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ index: Int, at elapsed: Double, from origin: CGPoint, fade: Double, on canvas: inout GraphicsContext) {
        let seed = Double(index)
        // Spread the launch angles across the upper half, by the golden ratio so they never clump.
        let angle = -Double.pi * (0.12 + 0.76 * (seed * 0.618).truncatingRemainder(dividingBy: 1))
        let speed = 260 + 240 * (seed * 0.37).truncatingRemainder(dividingBy: 1)
        let x = origin.x + cos(angle) * speed * elapsed
        let y = origin.y + sin(angle) * speed * elapsed + 0.5 * Self.gravity * elapsed * elapsed
        let side = 6 + 5 * (seed * 0.53).truncatingRemainder(dividingBy: 1)
        let spin = seed + elapsed * (4 + 6 * (seed * 0.29).truncatingRemainder(dividingBy: 1))

        var particle = canvas
        particle.translateBy(x: x, y: y)
        particle.rotate(by: .radians(spin))
        particle.fill(
            Path(roundedRect: CGRect(x: -side / 2, y: -side / 3, width: side, height: side * 0.66), cornerRadius: 1.5),
            with: .color(Self.palette[index % Self.palette.count].opacity(fade))
        )
    }
}
