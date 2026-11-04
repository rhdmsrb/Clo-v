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

    /// True once the viewer has picked a look, so the others can dim.
    var hasMyVote = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let zoomTapSize: CGFloat = 44
    private static let zoomVisualSize: CGFloat = 28
    private static let badgeSize: CGFloat = 28
    private static let chosenScale: CGFloat = 1.03
    private static let dimmedOpacity: Double = 0.9
    private static let percentMinScale: CGFloat = 0.7
    private static let edgeInset: CGFloat = 8
    private static let myVoteRingWidth: CGFloat = 3
    /// Fixed light track so navy text keeps >= 4.5:1 over both the track and the pink fill in dark mode.
    private static let trackColor = Color.white

    var body: some View {
        ZStack(alignment: .topTrailing) {
            voteButton
            zoomButton
        }
        .scaleEffect(isMine && revealed ? Self.chosenScale : 1)
        .opacity(revealed && hasMyVote && !isMine ? Self.dimmedOpacity : 1)
        .motionSafeAnimation(Theme.bounce, value: revealed)
        .accessibilityElement(children: .contain)
    }

    private var voteButton: some View {
        Button(action: onVote) {
            AspectFitTile(cornerRadius: Theme.tileRadius, shadow: false) {
                RemoteImage(url: photo.imageUrl)
                    .clipped()
                    .overlay(alignment: .bottom) { Theme.photoScrim }
                    .overlay(alignment: .topLeading) { positionBadge }
                    .overlay(alignment: .bottom) { footer }
            }
            .overlay {
                if isMine {
                    RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: Self.myVoteRingWidth)
                }
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
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(Self.percentMinScale)
            .frame(minWidth: Self.badgeSize, minHeight: Self.badgeSize)
            .background(Theme.card, in: Circle())
            .padding(Self.edgeInset)
            .accessibilityHidden(true)
    }

    private var footer: some View {
        Group {
            if revealed {
                VStack(alignment: .leading, spacing: 6) {
                    statusBadges
                    resultPill
                }
            } else {
                tapToVotePill
            }
        }
        .padding(Self.edgeInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var tapToVotePill: some View {
        Label("Tap to vote", systemImage: "hand.tap.fill")
            .font(Theme.micro)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(Self.percentMinScale)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.card, in: Capsule())
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    /// Crown for the leader and a check for your vote. Each pairs an icon
    /// with text so state never relies on color alone.
    private var statusBadges: some View {
        HStack(spacing: 4) {
            if isLeading {
                ViewThatFits(in: .horizontal) {
                    leadingBadge(showsText: true)
                    leadingBadge(showsText: false)
                }
            }
            if isMine {
                ViewThatFits(in: .horizontal) {
                    mineBadge(showsText: true)
                    mineBadge(showsText: false)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func leadingBadge(showsText: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "crown.fill").foregroundStyle(Theme.win)
            if showsText { Text("Leading").lineLimit(1) }
        }
        .font(Theme.micro)
        .foregroundStyle(Theme.accentForeground)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Self.trackColor, in: Capsule())
    }

    private func mineBadge(showsText: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.accentForeground, Theme.accent)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : revealed)
            if showsText { Text("Your vote").lineLimit(1) }
        }
        .font(Theme.micro)
        .foregroundStyle(Theme.accentForeground)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Self.trackColor, in: Capsule())
    }

    /// Opaque capsule whose accent fill grows from the leading edge to the look's share.
    private var resultPill: some View {
        Text("\(percent)%")
            .font(Theme.font(.title3, weight: .heavy))
            .foregroundStyle(Theme.accentForeground)
            .contentTransition(.numericText(value: Double(percent)))
            .animation(Theme.animation(.snappy, reduceMotion: reduceMotion), value: percent)
            .lineLimit(1)
            .minimumScaleFactor(Self.percentMinScale)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) { ResultBar(percent: percent) }
            .background(Self.trackColor)
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }

    // Zoom is its own control: a double-tap gesture on the tile would also
    // fire the tile's vote button on the first tap.
    private var zoomButton: some View {
        Button(action: onZoom) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(width: Self.zoomVisualSize, height: Self.zoomVisualSize)
                .background(Theme.card, in: Circle())
                .frame(width: Self.zoomTapSize, height: Self.zoomTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zoom look \(photo.position)")
    }
}

/// Accent fill behind the result pill that grows from the leading edge to the look's share of votes.
private struct ResultBar: View {
    let percent: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Theme.accent)
                .frame(width: proxy.size.width * (filled ? CGFloat(percent) / 100 : 0))
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(Theme.animation(Theme.hero, reduceMotion: reduceMotion)) { filled = true }
        }
        .animation(Theme.animation(Theme.settle, reduceMotion: reduceMotion), value: percent)
        .accessibilityHidden(true)
    }
}
