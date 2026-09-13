import SwiftUI

/// The 3:4 aspect-fit "photo tile" sizing shared by the create-flow
/// photo slots and the voting grid: `Color.clear` sized via
/// `.aspectRatio(_, contentMode: .fit)` can only ever shrink to stay
/// inside whatever width its container proposes, never grow — unlike
/// sizing real image content directly, which can blow up past its box
/// in an unbounded scroll context. Real content is overlaid into the
/// already-sized box, then clipped and shadowed as one tile.
///
/// `overlay` supplies everything that should be clipped to the tile's
/// rounded corners (the photo/placeholder, any on-image badge). Chrome
/// that shouldn't be clipped — e.g. a "this is my vote" ring — belongs
/// in a plain `.overlay` chained onto the call site instead.
struct AspectFitTile<Overlay: View>: View {
    var cornerRadius: CGFloat = Theme.tileRadius
    var shadow: Bool = true
    @ViewBuilder var overlay: () -> Overlay

    var body: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(content: overlay)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .layeredShadow(shadow ? Theme.cardShadow : .clear)
    }
}
