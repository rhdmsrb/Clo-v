import SwiftUI

/// Press-and-hold (~0.6s) to vote, with a progress ring and haptics.
/// Early lift or sliding away cancels. VoiceOver gets a plain action instead.
struct HoldToVoteGesture: ViewModifier {
    var isEnabled: Bool = true
    /// Mirrors whether a hold is in progress, so a parent can pause auto-advancing photos while it lasts.
    var isPressing: Binding<Bool>?
    let onVote: () -> Void

    private static let slopDistance: CGFloat = 24
    private static let tickNanoseconds: UInt64 = 16_000_000
    private static let burstDuration: TimeInterval = 0.5
    private static let ringSize: CGFloat = 72
    private static let voteHint = "Hold to vote, or use the Actions rotor to vote for this look"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hold = HoldProgress.idle
    @State private var ticker: Task<Void, Never>?
    @State private var showBurst = false
    @State private var burstTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        // Always the same view structure so @State (burst, hold) survives
        // isEnabled flipping false right after an optimistic vote.
        content
            .overlay { ring }
            .onLongPressGesture(
                minimumDuration: HoldProgress.duration,
                maximumDistance: Self.slopDistance,
                perform: { if isEnabled { finish() } },
                onPressingChanged: { pressing in
                    guard isEnabled else { return cancel() }
                    pressing ? start() : cancel()
                }
            )
            .accessibilityActions {
                if isEnabled { Button("Vote for this look", action: onVote) }
            }
            .accessibilityHint(isEnabled ? Self.voteHint : "")
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { cancel() }
            }
            .onDisappear { tearDown() }
    }

    @ViewBuilder
    private var ring: some View {
        ZStack {
            if hold.phase == .holding {
                Circle().stroke(.white.opacity(0.3), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: hold.progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "heart.fill").foregroundStyle(.white).font(.title2)
            }
            if showBurst {
                Circle()
                    .stroke(Theme.accent, lineWidth: 4)
                    .scaleEffect(reduceMotion ? 1 : 2.2)
                    .opacity(0)
                    .transition(.opacity)
                Image(systemName: "heart.fill").foregroundStyle(Theme.accent).font(.largeTitle)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .shadow(color: .black.opacity(0.35), radius: 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func start() {
        guard hold.phase == .idle else { return }
        hold = hold.begin()
        isPressing?.wrappedValue = true
        Haptics.impact(.light)
        let startedAt = Date()
        ticker?.cancel()
        ticker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.tickNanoseconds)
                guard !Task.isCancelled else { return }
                let previous = hold
                hold = hold.tick(elapsed: Date().timeIntervalSince(startedAt))
                if hold.crossedMilestones(since: previous) > 0 { Haptics.impact(.light) }
            }
        }
    }

    private func cancel() {
        ticker?.cancel()
        ticker = nil
        isPressing?.wrappedValue = false
        if hold.phase != .completed { hold = hold.cancel() }
    }

    private func finish() {
        ticker?.cancel()
        ticker = nil
        guard hold.phase == .holding else { return }
        isPressing?.wrappedValue = false
        hold = hold.complete()
        // Success haptic is fired by the vote model (covers the accessibility path too).
        Haptics.impact(.heavy)
        withAnimation(reduceMotion ? nil : Theme.snap) { showBurst = true }
        onVote()
        burstTask?.cancel()
        burstTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.burstDuration))
            guard !Task.isCancelled else { return }
            showBurst = false
            hold = hold.reset()
        }
    }

    /// Cancels the burst timer and returns to idle so nothing is left `.completed`.
    private func tearDown() {
        burstTask?.cancel()
        burstTask = nil
        cancel()
        showBurst = false
        hold = hold.reset()
    }
}

extension View {
    /// Hold ~0.6s to vote. Adds the "Vote for this look" accessibility action.
    func holdToVote(isEnabled: Bool = true, isPressing: Binding<Bool>? = nil,
                    onVote: @escaping () -> Void) -> some View {
        modifier(HoldToVoteGesture(isEnabled: isEnabled, isPressing: isPressing, onVote: onVote))
    }
}

#Preview("HoldToVote") {
    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        .fill(Theme.accentTint)
        .frame(height: 280)
        .holdToVote { }
        .padding()
}
