import SwiftUI

/// One tappable photo in the voting grid, with a sibling zoom control.
struct VoteTile: View {
    let photo: FitCheckPhoto
    let percent: Int
    let revealed: Bool
    let isLeading: Bool
    let isMine: Bool
    let canVote: Bool
    let isDisabled: Bool
    let onVote: () -> Void
    let onZoom: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let zoomTapSize: CGFloat = 44
    private static let zoomVisualSize: CGFloat = 28
    private static let footerMinHeight: CGFloat = 36
    private static let footerMinScale: CGFloat = 0.6

    var body: some View {
        ZStack(alignment: .topTrailing) {
            voteButton
            zoomButton
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75), value: revealed)
        .accessibilityElement(children: .contain)
    }

    private var voteButton: some View {
        Button(action: onVote) {
            AspectFitTile(cornerRadius: Theme.smallRadius, shadow: false) {
                RemoteImage(url: photo.imageUrl)
                    .clipped()
                    .overlay(alignment: .topLeading) { positionBadge }
                    .overlay(alignment: .bottom) { footer }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .stroke(isMine ? Theme.accentSecondary : Theme.ink, lineWidth: isMine ? 3 : 1)
            }
        }
        .buttonStyle(TileButtonStyle())
        // Not `.disabled`: VoiceOver would announce the tile as "dimmed".
        // `onVote`'s callers also guard against revealed/in-flight votes.
        .allowsHitTesting(!(revealed || isDisabled))
        .accessibilityRemoveTraits(revealed ? .isButton : [])
        .accessibilityLabel("Look \(photo.position)")
        .accessibilityValue(revealed ? "\(percent) percent of votes\(isLeading ? ", leading" : "")\(isMine ? ", your vote" : "")" : "")
        .accessibilityHint(revealed ? "Results are shown" : (canVote ? "Casts your vote for this look" : ""))
        .accessibilityAddTraits(isMine ? .isSelected : [])
    }

    private var positionBadge: some View {
        Text(String(format: "%02d", photo.position))
            .font(Theme.micro)
            .foregroundStyle(Theme.inverseText)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Theme.ink)
    }

    private var footer: some View {
        Group {
            if revealed {
                // Drops the "LEADS" word before it would wrap; the percent
                // always stays on one line. Full wording lives in the
                // tile's accessibilityValue.
                ViewThatFits(in: .horizontal) {
                    resultRow(showsLeadLabel: true)
                    resultRow(showsLeadLabel: false)
                }
            } else {
                Text("VOTE").font(Theme.micro).lineLimit(1)
            }
        }
        .foregroundStyle(Theme.inverseText)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: Self.footerMinHeight)
        // The bar goes first so the ink fill (added last) sits behind it.
        .background(alignment: .leading) { if revealed { ResultBar(percent: percent, isMine: isMine) } }
        .background(Theme.ink)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func resultRow(showsLeadLabel: Bool) -> some View {
        HStack(spacing: 4) {
            Text("\(percent)%")
                .font(.headline.weight(.black))
                .contentTransition(.numericText(value: Double(percent)))
                .animation(reduceMotion ? nil : .snappy, value: percent)
                .lineLimit(1)
                .minimumScaleFactor(Self.footerMinScale)
            if isLeading {
                if showsLeadLabel && !dynamicTypeSize.isAccessibilitySize {
                    Label("LEADS", systemImage: "star.fill")
                        .font(Theme.micro)
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    Image(systemName: "star.fill").font(Theme.micro)
                }
            }
            if isMine {
                Image(systemName: "checkmark").font(Theme.micro)
            }
        }
        .accessibilityHidden(true)
    }

    // Zoom is its own control: a double-tap gesture on the tile would also
    // fire the tile's vote button on the first tap.
    private var zoomButton: some View {
        Button(action: onZoom) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.inverseText)
                .frame(width: Self.zoomVisualSize, height: Self.zoomVisualSize)
                .background(Theme.ink.opacity(0.75))
                .clipShape(Circle())
                .frame(width: Self.zoomTapSize, height: Self.zoomTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zoom look \(photo.position)")
    }
}

/// Accent fill behind the result footer that grows to the look's share of votes.
private struct ResultBar: View {
    let percent: Int
    let isMine: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Theme.accent.opacity(isMine ? 0.45 : 0.3))
                .frame(width: proxy.size.width * (filled ? CGFloat(percent) / 100 : 0))
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.8)) { filled = true }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: percent)
        .accessibilityHidden(true)
    }
}
