import SwiftUI

/// Placeholder layouts shown by `AsyncStateView` while the first load runs.
enum SkeletonStyle {
    case spinner, cards, grid, rows
}

/// Sweeping highlight over the placeholder shapes. Static under Reduce Motion.
private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = 0

    private static let sweepWidthFraction: CGFloat = 0.6

    func body(content: Content) -> some View {
        content
            .overlay { if !reduceMotion { sweep.mask(content) } }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }

    private var sweep: some View {
        GeometryReader { geo in
            let width = geo.size.width * Self.sweepWidthFraction
            LinearGradient(
                colors: [.clear, Color.white.opacity(colorScheme == .dark ? 0.10 : 0.6), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width)
            .offset(x: -width + phase * (geo.size.width + width))
        }
        .allowsHitTesting(false)
    }
}

private struct SkeletonBlock: View {
    var cornerRadius: CGFloat = Theme.cardRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Theme.muted)
    }
}

struct SkeletonView: View {
    let style: SkeletonStyle

    var body: some View {
        Group {
            switch style {
            case .spinner: ProgressView()
            case .cards: VStack(spacing: 16) { ForEach(0..<2, id: \.self) { _ in card } }
            case .grid: grid
            case .rows: VStack(spacing: 14) { ForEach(0..<5, id: \.self) { _ in row } }
            }
        }
        .modifier(Shimmer())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SkeletonBlock(cornerRadius: Theme.cardRadius).frame(width: 36, height: 36)
                SkeletonBlock(cornerRadius: Theme.smallRadius).frame(width: 120, height: 14)
            }
            HStack(spacing: 8) {
                SkeletonBlock().aspectRatio(0.75, contentMode: .fit)
                SkeletonBlock().aspectRatio(0.75, contentMode: .fit)
            }
            SkeletonBlock(cornerRadius: Theme.smallRadius).frame(width: 180, height: 12)
        }
        .padding(14)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)], spacing: 14) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBlock().aspectRatio(0.8, contentMode: .fit)
                    SkeletonBlock(cornerRadius: Theme.smallRadius).frame(width: 90, height: 12)
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            SkeletonBlock(cornerRadius: Theme.cardRadius).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(cornerRadius: Theme.smallRadius).frame(height: 13)
                SkeletonBlock(cornerRadius: Theme.smallRadius).frame(width: 140, height: 11)
            }
        }
    }
}
