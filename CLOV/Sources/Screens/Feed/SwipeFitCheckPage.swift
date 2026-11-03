import SwiftUI

/// One full-screen Fit-Check in the reel. Swipe right to vote for the look
/// on screen, swipe left for the next look, swipe up for the next Fit-Check.
struct SwipeFitCheckPage: View {
    let item: FeedItemDTO
    let voterId: UUID
    let isFollowing: Bool
    let onToggleFollow: (Bool) -> Void
    let onEvent: (String) -> Void
    let onImpression: () -> Void

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: ReelVoteModel
    @State private var drag: CGSize = .zero
    @State private var hasSwiped = false

    private static let bottomInset: CGFloat = 112
    private static let lookIndicatorTopPadding: CGFloat = 112
    private static let maxTiltDegrees: Double = 6
    private static let dragFollowRatio: CGFloat = 0.6

    init(item: FeedItemDTO, voterId: UUID, isFollowing: Bool, onToggleFollow: @escaping (Bool) -> Void,
         onEvent: @escaping (String) -> Void, onImpression: @escaping () -> Void) {
        self.item = item
        self.voterId = voterId
        self.isFollowing = isFollowing
        self.onToggleFollow = onToggleFollow
        self.onEvent = onEvent
        self.onImpression = onImpression
        _model = StateObject(wrappedValue: ReelVoteModel(item: item, voterId: voterId))
    }

    private var nickname: String { item.profiles?.nickname ?? "Someone" }
    private var canFollow: Bool { item.creatorId != voterId }
    private var progress: CGFloat { SwipeVoteGesture.progress(for: drag) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                photoLayer(size: proxy.size)
                Theme.photoScrim
                stamps
                HStack(alignment: .bottom, spacing: 18) {
                    infoColumn
                    actionRail
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.bottom, Self.bottomInset)
            }
            .overlay(alignment: .top) { lookIndicator }
            .contentShape(Rectangle())
            .simultaneousGesture(swipeGesture)
            .onAppear(perform: onImpression)
        }
        .accessibilityAction(named: "Vote for this look") { castVote() }
        .accessibilityAction(named: "Show next look") { model.showLook(step: 1) }
        .sensoryFeedback(.selection, trigger: model.lookIndex)
    }

    // MARK: Photo and gesture

    @ViewBuilder
    private func photoLayer(size: CGSize) -> some View {
        if let photo = model.currentPhoto {
            RemoteImage(url: photo.imageUrl, label: "Look \(photo.position) by \(nickname)")
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .id(photo.id)
                .transition(.opacity)
                .offset(x: progress * SwipeVoteGesture.commitDistance * Self.dragFollowRatio)
                .rotationEffect(.degrees(Double(progress) * Self.maxTiltDegrees))
                .animation(reduceMotion ? nil : .snappy, value: model.lookIndex)
        } else {
            Theme.muted
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                // Only horizontal drags move the photo; vertical ones belong to the pager.
                drag = value.translation
            }
            .onEnded { value in
                let action = SwipeVoteGesture.action(for: value.translation, canVote: model.canVote)
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) { drag = .zero }
                perform(action)
            }
    }

    private func perform(_ action: SwipeVoteAction) {
        switch action {
        case .vote: castVote()
        case .nextLook: hasSwiped = true; model.showLook(step: 1)
        case .previousLook: hasSwiped = true; model.showLook(step: -1)
        case .none: break
        }
    }

    private func castVote() {
        hasSwiped = true
        let started = model.voteForCurrentLook {
            appState.contentDidChange()
        }
        if started { Haptics.impact(.medium) }
    }

    // MARK: Overlays

    /// "VOTE" fades in as you drag right; "NEXT LOOK" as you drag left.
    private var stamps: some View {
        ZStack {
            if model.canVote {
                stamp("VOTE", systemImage: "heart.fill", tint: Theme.accent)
                    .opacity(max(0, progress))
                    .scaleEffect(0.8 + 0.3 * max(0, progress))
            }
            stamp("NEXT LOOK", systemImage: "arrow.left", tint: .white)
                .opacity(max(0, -progress))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stamp(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title2.weight(.black))
            .foregroundStyle(tint)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(.black.opacity(0.45), in: Capsule())
            .overlay(Capsule().stroke(tint, lineWidth: 3))
    }

    @ViewBuilder
    private var lookIndicator: some View {
        if model.photos.count > 1 {
            HStack(spacing: 6) {
                ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, _ in
                    Capsule()
                        .fill(index == model.lookIndex ? Color.white : Color.white.opacity(0.4))
                        .frame(width: index == model.lookIndex ? 22 : 8, height: 4)
                }
            }
            .padding(.top, Self.lookIndicatorTopPadding)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Look \(model.lookIndex + 1) of \(model.photos.count)")
        }
    }

    // MARK: Info

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Text("@\(nickname)")
                    .font(.subheadline.weight(.bold))
                if canFollow { followPill }
            }
            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(3)
            }
            voteStatus
            detailLink {
                Label("Open Fit-Check", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.18), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var voteStatus: some View {
        if let myVote = model.myVote, let insight = model.insight {
            VStack(alignment: .leading, spacing: 4) {
                Text("You picked look \(model.photos.first { $0.id == myVote }?.position ?? 1) · \(model.percent(for: myVote))%")
                    .font(.footnote.weight(.black))
                Text(insight).font(.caption.weight(.medium))
                if let summary = model.streak.summary() {
                    Label(summary, systemImage: "flame.fill").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                }
                Text("Swipe up for the next look").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            .padding(10)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityElement(children: .combine)
        } else if let error = model.error {
            Text(error).font(.caption.weight(.semibold)).foregroundStyle(Theme.danger)
        } else if model.canVote {
            swipeHint
        }
    }

    private var swipeHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw").accessibilityHidden(true)
            Text(model.isFirstTimeVoter && !hasSwiped ? "Swipe right to vote · left for the next look" : "Swipe right to vote")
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(0.18), in: Capsule())
        .accessibilityHidden(true)
    }

    private var followPill: some View {
        Button(isFollowing ? "Following" : "+ Follow") {
            onToggleFollow(!isFollowing)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(isFollowing ? Color.white : Theme.accentForeground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isFollowing ? .white.opacity(0.18) : Theme.accent, in: Capsule())
        .frame(minHeight: FeedLayout.minHitSize)
        .contentShape(Rectangle())
        .accessibilityLabel("Follow \(nickname)")
        .accessibilityValue(isFollowing ? "Following" : "Not following")
        .accessibilityAddTraits(.isToggle)
    }

    // MARK: Action rail

    private var actionRail: some View {
        VStack(spacing: 18) {
            avatarButton
            detailLink { feedAction("heart.fill", count: model.total, label: "Votes") }
            detailLink { feedAction("bubble.right.fill", count: item.fitCheckComments.count, label: "Comments") }
            ShareLink(item: "Check out this Fit-Check on CLO·V") {
                feedAction("paperplane.fill", count: nil, label: "Share")
            }
            .simultaneousGesture(TapGesture().onEnded { onEvent("share") })
        }
        .frame(width: 50)
    }

    private var avatarButton: some View {
        Button {
            guard canFollow else { return }
            onToggleFollow(!isFollowing)
        } label: {
            AvatarView(url: item.profiles?.avatarUrl, nickname: item.profiles?.nickname, size: 46, ringed: true)
                .overlay(alignment: .bottom) {
                    if canFollow {
                        Image(systemName: isFollowing ? "checkmark" : "plus")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(Theme.accentForeground)
                            .frame(width: 20, height: 20)
                            .background(Theme.accent, in: Circle())
                            .offset(y: 8)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!canFollow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Follow \(nickname)")
        .accessibilityValue(isFollowing ? "Following" : "Not following")
        .accessibilityAddTraits([.isButton, .isToggle])
        .accessibilityHidden(!canFollow)
    }

    private func detailLink<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        NavigationLink {
            FitCheckDetailView(fitCheckId: item.id)
        } label: {
            label()
        }
        .simultaneousGesture(TapGesture().onEnded { onEvent("open_detail") })
    }

    private func feedAction(_ symbol: String, count: Int?, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            if let count {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
            }
        }
        .frame(minWidth: 48, minHeight: 46)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { "\(label), \($0)" } ?? label)
    }
}
