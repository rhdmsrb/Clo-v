import CoreGraphics

/// Pure column assignment for `MasonryGrid`.
enum MasonryLayout {
    /// Aspect ratios (width / height) are clamped so extreme photos can't make
    /// a tile absurdly tall or flat.
    static let ratioRange: ClosedRange<CGFloat> = 0.5...2

    static func clampedRatio(_ ratio: CGFloat) -> CGFloat {
        guard ratio.isFinite, ratio > 0 else { return 1 }
        return min(max(ratio, ratioRange.lowerBound), ratioRange.upperBound)
    }

    /// Greedy shortest-column placement. Columns share one width, so a tile's
    /// relative height is `1 / ratio`. Ties go to the leftmost column.
    /// Returns item indices per column, in order.
    static func assign(aspectRatios: [CGFloat], columnCount: Int = 2) -> [[Int]] {
        let count = max(columnCount, 1)
        var columns = [[Int]](repeating: [], count: count)
        var heights = [CGFloat](repeating: 0, count: count)
        for (index, ratio) in aspectRatios.enumerated() {
            let target = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[target].append(index)
            heights[target] += 1 / clampedRatio(ratio)
        }
        return columns
    }
}
