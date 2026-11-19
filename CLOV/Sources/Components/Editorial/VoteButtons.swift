import SwiftUI

/// One look in a `VoteButtons` group.
struct VoteOption: Identifiable, Equatable {
    let id: UUID
    let title: String
    /// Share of the votes, 0...100. Ignored until results are revealed.
    let percent: Int
    var isLeading = false
}

/// Pill vote buttons, one per look. Before voting they are plain pills (the look on
/// screen is outlined in ink); after voting, or when results are open to the viewer,
/// each pill becomes a result bar that fills to its share, with a check on the viewer's
/// pick. Presentational only: the caller casts and undoes the vote.
struct VoteButtons: View {
    let options: [VoteOption]
    /// The look currently showing in the photo above, emphasised before voting.
    var highlightedID: UUID? = nil
    let myVote: UUID?
    let isRevealed: Bool
    let canVote: Bool
    /// Shown under the results ("128 votes", "Voting ended · 40 votes").
    var footer: String? = nil
    /// Prefix for accessibility identifiers: `<prefix>-button-N`, `<prefix>-results`, `<prefix>-undo`.
    var identifierPrefix = "vote"
    let onVote: (UUID) -> Void
    var onUndo: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 -> 1 when results are revealed, so the bars grow from empty.
    @State private var fillProgress: CGFloat = 0

    private static let pillHeight: CGFloat = Theme.minTapSize
    private static let barSpacing: CGFloat = Spacing.s

    var body: some View {
        Group {
            if isRevealed { results } else { pills }
        }
        .onAppear { setFill(revealed: isRevealed, animated: false) }
        .onChange(of: isRevealed) { _, revealed in setFill(revealed: revealed, animated: true) }
    }

    // MARK: Before voting

    private var pills: some View {
        HStack(spacing: Self.barSpacing) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                let isHighlighted = option.id == highlightedID
                Button {
                    Haptics.impact(.medium)
                    onVote(option.id)
                } label: {
                    Text(option.title)
                        .font(Theme.font(.subheadline, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: Self.pillHeight)
                        .background(Theme.card, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(isHighlighted ? Theme.ink : Theme.controlBorder,
                                              lineWidth: isHighlighted ? 1.5 : 1)
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(VotePressStyle())
                .disabled(!canVote)
                .opacity(canVote ? 1 : 0.5)
                .accessibilityLabel("Vote for \(option.title)")
                .accessibilityIdentifier("\(identifierPrefix)-button-\(index + 1)")
            }
        }
        .motionSafeAnimation(Theme.quick, value: highlightedID)
    }

    // MARK: After voting

    private var results: some View {
        VStack(alignment: .leading, spacing: Self.barSpacing) {
            ForEach(options) { resultBar($0) }
            if footer != nil || onUndo != nil {
                HStack {
                    if let footer {
                        Text(footer)
                            .font(Theme.micro)
                            .foregroundStyle(Theme.mutedForeground)
                    }
                    Spacer(minLength: 0)
                    if let onUndo { undoButton(onUndo) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix)-results")
    }

    private func resultBar(_ option: VoteOption) -> some View {
        let isMine = option.id == myVote
        return HStack(spacing: Spacing.xs + 2) {
            if isMine { Image(systemName: "checkmark.circle.fill") }
            Text(option.title).lineLimit(1)
            if option.isLeading { Image(systemName: "crown.fill").imageScale(.small) }
            Spacer(minLength: Spacing.s)
            Text("\(option.percent)%")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(Theme.font(.subheadline, weight: isMine ? .bold : .semibold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, Spacing.m)
        .frame(maxWidth: .infinity, minHeight: Self.pillHeight)
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous).fill(Theme.muted)
                    Capsule(style: .continuous)
                        .fill(isMine ? Theme.accent.opacity(0.85) : Theme.accent.opacity(0.35))
                        .frame(width: max(proxy.size.height, proxy.size.width * CGFloat(option.percent) / 100 * fillProgress))
                        .opacity(option.percent == 0 ? 0 : 1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(option.title), \(option.percent) percent\(isMine ? ", your vote" : "")\(option.isLeading ? ", leading" : "")")
    }

    private func undoButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Undo")
                .font(Theme.font(.footnote, weight: .semibold))
                .foregroundStyle(Theme.accentDeep)
                .padding(.horizontal, Spacing.sm)
                .frame(minHeight: Theme.minTapSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Undo vote")
        .accessibilityIdentifier("\(identifierPrefix)-undo")
    }

    private func setFill(revealed: Bool, animated: Bool) {
        let target: CGFloat = revealed ? 1 : 0
        guard animated, !reduceMotion else {
            fillProgress = target
            return
        }
        fillProgress = 0
        withAnimation(Theme.settle.delay(0.05)) { fillProgress = target }
    }
}

private struct VotePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .motionSafeAnimation(Theme.press, value: configuration.isPressed)
    }
}

#Preview("Vote buttons") {
    struct Demo: View {
        @State private var myVote: UUID?
        let ids = [UUID(), UUID(), UUID()]
        var options: [VoteOption] {
            [VoteOption(id: ids[0], title: "Look 1", percent: 58, isLeading: true),
             VoteOption(id: ids[1], title: "Look 2", percent: 27),
             VoteOption(id: ids[2], title: "Look 3", percent: 15)]
        }
        var body: some View {
            VoteButtons(options: options, highlightedID: ids[0], myVote: myVote,
                        isRevealed: myVote != nil, canVote: true, footer: "128 votes",
                        onVote: { myVote = $0 }, onUndo: { myVote = nil })
                .padding(Spacing.m)
                .background(Theme.card)
        }
    }
    return Demo()
}
