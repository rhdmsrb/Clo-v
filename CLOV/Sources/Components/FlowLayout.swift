import SwiftUI

/// A simple wrapping layout for chip rows (style picker, tags).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    /// Where each chip goes (relative to the layout's top-left) and the size that holds them all.
    struct Arrangement: Equatable {
        let origins: [CGPoint]
        let size: CGSize
    }

    /// The single place rows are broken, used for both measuring and placing. A chip wraps
    /// when it does not fit after the gap that precedes it. Measuring and placing each used
    /// their own check, and the measuring one left the gap out: a chip that fit only without
    /// the gap was counted on the first row but placed on the next, so the container was one
    /// row too short and the last chips drew over whatever sat below it.
    static func arrange(sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat) -> Arrangement {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for size in sizes {
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return Arrangement(origins: origins, size: CGSize(width: maxWidth, height: sizes.isEmpty ? 0 : y + rowHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return Self.arrange(sizes: sizes, maxWidth: proposal.width ?? .infinity, spacing: spacing).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let arrangement = Self.arrange(sizes: sizes, maxWidth: bounds.width, spacing: spacing)

        for (index, subview) in subviews.enumerated() {
            let origin = arrangement.origins[index]
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          proposal: ProposedViewSize(sizes[index]))
        }
    }
}
