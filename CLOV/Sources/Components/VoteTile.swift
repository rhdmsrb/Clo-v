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

    private static let zoomTapSize: CGFloat = 44
    private static let zoomVisualSize: CGFloat = 28

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
                    .stroke(isMine ? Theme.accent : Theme.ink, lineWidth: isMine ? 3 : 1)
            }
        }
        .buttonStyle(TileButtonStyle())
        // Not `.disabled`: VoiceOver would announce the tile as "dimmed".
        // `onVote`'s callers also guard against revealed/in-flight votes.
        .allowsHitTesting(!(revealed || isDisabled))
        .accessibilityRemoveTraits(revealed ? .isButton : [])
        .accessibilityLabel("Look \(photo.position + 1)")
        .accessibilityValue(revealed ? "\(percent) percent of votes\(isLeading ? ", leading" : "")\(isMine ? ", your vote" : "")" : "")
        .accessibilityHint(revealed ? "Results are shown" : (canVote ? "Casts your vote for this look" : ""))
        .accessibilityAddTraits(isMine ? .isSelected : [])
    }

    private var positionBadge: some View {
        Text(String(format: "%02d", photo.position + 1))
            .font(Theme.micro)
            .foregroundStyle(Theme.inverseText)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Theme.ink)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if revealed {
                Text("\(percent)%").font(.headline.weight(.black))
                if isLeading {
                    Label("LEADS", systemImage: "star.fill")
                        .font(Theme.micro)
                        .labelStyle(.titleAndIcon)
                }
                if isMine {
                    Image(systemName: "checkmark").font(Theme.micro)
                }
            } else {
                Text("VOTE").font(Theme.micro)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.inverseText)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(Theme.ink)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
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
        .accessibilityLabel("Zoom look \(photo.position + 1)")
    }
}
