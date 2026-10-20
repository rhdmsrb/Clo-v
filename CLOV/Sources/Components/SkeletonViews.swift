import SwiftUI

/// Placeholder layouts shown by `AsyncStateView` while the first load runs.
enum SkeletonStyle {
    case spinner, cards, grid, rows
}

private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBright = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || isBright ? 1 : 0.55)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isBright)
            .onAppear { isBright = true }
    }
}

private struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 10

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
                SkeletonBlock(cornerRadius: 18).frame(width: 36, height: 36)
                SkeletonBlock(cornerRadius: 5).frame(width: 120, height: 14)
            }
            HStack(spacing: 8) {
                SkeletonBlock().aspectRatio(0.75, contentMode: .fit)
                SkeletonBlock().aspectRatio(0.75, contentMode: .fit)
            }
            SkeletonBlock(cornerRadius: 5).frame(width: 180, height: 12)
        }
        .padding(14)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)], spacing: 14) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBlock().aspectRatio(0.8, contentMode: .fit)
                    SkeletonBlock(cornerRadius: 5).frame(width: 90, height: 12)
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            SkeletonBlock(cornerRadius: 22).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(cornerRadius: 5).frame(height: 13)
                SkeletonBlock(cornerRadius: 5).frame(width: 140, height: 11)
            }
        }
    }
}
