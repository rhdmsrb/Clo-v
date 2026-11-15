import SwiftUI

/// Horizontal cover-flow of a Fit-Check's photos. The centred photo is large;
/// neighbours peek at both edges, smaller and tilted. Hold-to-vote applies only
/// to the centred photo, and each photo shows its own result chip once revealed.
struct PhotoFan: View {
    let photos: [FitCheckPhoto]
    @Binding var selection: Int
    let canVote: Bool
    let isResultsRevealed: Bool
    let percent: (UUID) -> Int
    let myVote: UUID?
    let onVote: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrolledIndex: Int?

    private static let cardWidthFraction: CGFloat = 0.62
    private static let cardAspect: CGFloat = 4.0 / 3.0
    private static let cardSpacing: CGFloat = 12
    private static let sideScale: CGFloat = 0.86
    private static let sideTiltDegrees: Double = 7
    private static let sideOpacity: Double = 0.7
    /// Width / height of the whole fan, so the height follows the card height.
    private static let fanAspect: CGFloat = 1 / (cardWidthFraction * cardAspect + 0.04)

    var body: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width * Self.cardWidthFraction
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Self.cardSpacing) {
                    ForEach(photos.indices, id: \.self) { index in
                        card(photos[index], index: index, width: cardWidth)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, (geo.size.width - cardWidth) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledIndex, anchor: .center)
            .frame(maxHeight: .infinity)
        }
        .aspectRatio(Self.fanAspect, contentMode: .fit)
        .onAppear { scrolledIndex = selection }
        .onChange(of: scrolledIndex) { _, newIndex in
            guard let newIndex, newIndex != selection else { return }
            selection = newIndex
        }
        .onChange(of: selection) { _, newSelection in
            guard scrolledIndex != newSelection else { return }
            scrolledIndex = newSelection
        }
        .accessibilityIdentifier("voteFan")
    }

    private func card(_ photo: FitCheckPhoto, index: Int, width: CGFloat) -> some View {
        // The hold modifier is always applied; only `isEnabled` changes, so its
        // burst state survives the vote flipping `canVote` to false.
        RemoteImage(url: photo.imageUrl, label: "Photo \(index + 1) of \(photos.count)")
            .scaledToFill()
            .frame(width: width, height: width * Self.cardAspect)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .holdToVote(isEnabled: canVote && index == selection, onVote: onVote)
            .overlay(alignment: .bottom) { resultChip(photo) }
            .scrollTransition(axis: .horizontal) { content, phase in
                content
                    .scaleEffect(phase.isIdentity ? 1 : Self.sideScale)
                    .rotationEffect(.degrees(reduceMotion ? 0 : phase.value * Self.sideTiltDegrees))
                    .opacity(phase.isIdentity ? 1 : Self.sideOpacity)
            }
    }

    private func resultChip(_ photo: FitCheckPhoto) -> some View {
        Text("\(percent(photo.id))%")
            .font(Theme.font(.subheadline, weight: photo.id == myVote ? .black : .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
            .blurReveal(isRevealed: isResultsRevealed)
            .padding(.bottom, 10)
            .allowsHitTesting(false)
    }
}
