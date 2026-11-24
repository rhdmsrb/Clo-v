import SwiftUI

/// Colours and sizes shared by the HUD-style vote controls on the feed card: a near-square
/// black block, monospaced labels, an orange gauge and orange corner ticks.
enum HudStyle {
    /// Always dark, in light and dark mode, so it reads the same over any photo.
    static let block = Color(uiColor: Theme.uiColor(hex: 0x111214))
    /// The bright accent: 7:1 on the black block, so it passes for small text.
    static let signal = Color(uiColor: Theme.uiColor(hex: 0xFF7A4D))
    static let dimText = Color(uiColor: Theme.uiColor(hex: 0xA6A8AE))
    static let track = Color.white.opacity(0.18)
    static let radius = Radius.hero
    static let tickSize: CGFloat = 6
    static let tickInset: CGFloat = 6
    static let tickLine: CGFloat = 1.5
    static let gaugeHeight: CGFloat = 2

    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }

    /// "LOOK_02" from a 1-based look position.
    static func lookCode(position: Int) -> String {
        String(format: "LOOK_%02d", max(position, 0))
    }

    /// A 0...1 fraction as a whole percentage, clamped.
    static func percent(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }
}

/// The big HUD block: a title ("VOTE", "✓ VOTED"), a look code, and a thin gauge with its
/// percentage. The gauge shows hold progress before a vote and the look's share after it.
struct HudVoteBlock: View {
    let title: String
    let detail: String?
    /// 0...1
    let fraction: Double
    /// Orange title and a filled gauge once the viewer has voted.
    let isVoted: Bool
    let minHeight: CGFloat
    /// True while the gauge follows a finger, so it tracks without easing.
    var isTracking = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var gaugeWidth: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(title)
                    .font(HudStyle.mono(.subheadline, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(isVoted ? HudStyle.signal : .white)
                if let detail {
                    Text(detail)
                        .font(HudStyle.mono(.caption))
                        .tracking(0.4)
                        .foregroundStyle(HudStyle.dimText)
                }
            }
            .lineLimit(1)
            HStack(spacing: Spacing.s) {
                gauge
                Text("\(HudStyle.percent(fraction))%")
                    .font(HudStyle.mono(.caption2, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(fraction > 0 ? HudStyle.signal : HudStyle.dimText)
                    .contentTransition(.numericText(value: fraction))
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.m)
        .frame(minHeight: minHeight)
        // Its own size, never squeezed by the icons beside it, so the look code and % stay whole.
        .fixedSize(horizontal: true, vertical: false)
        .background(HudStyle.block, in: RoundedRectangle(cornerRadius: HudStyle.radius, style: .continuous))
        .overlay { if !isVoted { HudCornerTicks() } }
        .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
    }

    private var gauge: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(HudStyle.track)
            Rectangle().fill(HudStyle.signal)
                .frame(width: gaugeWidth * min(max(fraction, 0), 1))
        }
        .frame(width: gaugeWidth, height: HudStyle.gaugeHeight)
        .animation(reduceMotion || isTracking ? nil : Theme.settle, value: fraction)
    }
}

/// Orange brackets at the top-right and bottom-left corners of the vote block.
private struct HudCornerTicks: View {
    var body: some View {
        ZStack {
            tick.rotationEffect(.degrees(90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            tick.rotationEffect(.degrees(-90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(HudStyle.tickInset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// An "L" opening to the bottom-right; rotated into each corner.
    private var tick: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: HudStyle.tickSize))
            path.addLine(to: .zero)
            path.addLine(to: CGPoint(x: HudStyle.tickSize, y: 0))
        }
        .stroke(HudStyle.signal, lineWidth: HudStyle.tickLine)
        .frame(width: HudStyle.tickSize, height: HudStyle.tickSize)
    }
}

/// Square outlined undo button that sits beside the voted block. Icon only, so the row
/// fits beside Like, Comment and the voted read-out on a narrow phone.
struct HudUndoButton: View {
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
                .font(.body.weight(.bold))
                .foregroundStyle(HudStyle.block)
                .frame(width: max(height * 0.85, Theme.minTapSize), height: height)
            .background(Color.white, in: RoundedRectangle(cornerRadius: HudStyle.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HudStyle.radius, style: .continuous)
                .strokeBorder(HudStyle.block, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(InstantPressStyle())
        .environment(\.colorScheme, .light)
        .accessibilityLabel("Undo vote")
        .accessibilityHint("Takes your vote back so you can pick again")
        .accessibilityIdentifier("feed-vote-undo")
    }
}

/// Small white near-square box with a black outline, for the Like and Comment icons.
struct HudIconBox: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.s)
            .frame(minWidth: height * 1.1, minHeight: height)
            // Natural width, so a like count never wraps onto two lines.
            .fixedSize()
            .background(Color.white, in: RoundedRectangle(cornerRadius: HudStyle.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HudStyle.radius, style: .continuous)
                .strokeBorder(HudStyle.block, lineWidth: 1))
            .environment(\.colorScheme, .light)
    }
}

#Preview("HUD vote controls") {
    VStack(spacing: 24) {
        HudVoteBlock(title: "VOTE", detail: "→ LOOK_02", fraction: 0, isVoted: false, minHeight: 52)
        HudVoteBlock(title: "VOTE", detail: "→ LOOK_02", fraction: 0.4, isVoted: false, minHeight: 52, isTracking: true)
        HStack(spacing: 6) {
            HudVoteBlock(title: "✓ VOTED", detail: "LOOK_02", fraction: 0.62, isVoted: true, minHeight: 52)
            HudUndoButton(height: 52) {}
        }
    }
    .padding()
    .background(Theme.background)
}
