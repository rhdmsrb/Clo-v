import SwiftUI

/// Pure rules for the reveal moment on the hold-to-vote screens.
enum VoteReveal {
    /// A lone first vote is trivially "leading", so confetti waits for a second.
    static let minVotesToCelebrate = 2

    /// Whole-number share of `total`, rounded to nearest.
    static func percent(count: Int, total: Int) -> Int {
        total > 0 ? Int((Double(max(count, 0)) / Double(total) * 100).rounded()) : 0
    }

    /// Photos holding the top count. Empty while nobody has votes, and empty when
    /// every one of several photos is tied (nothing is ahead).
    static func leadingIds(photoIds: [UUID], counts: [UUID: Int]) -> Set<UUID> {
        let top = photoIds.map { counts[$0] ?? 0 }.max() ?? 0
        guard top > 0 else { return [] }
        let leaders = Set(photoIds.filter { (counts[$0] ?? 0) == top })
        return photoIds.count > 1 && leaders.count == photoIds.count ? [] : leaders
    }

    /// Confetti when the viewer backed a leading look and the result is not trivial.
    static func shouldCelebrate(myVote: UUID?, photoIds: [UUID], counts: [UUID: Int], total: Int) -> Bool {
        guard let myVote, total >= minVotesToCelebrate else { return false }
        return leadingIds(photoIds: photoIds, counts: counts).contains(myVote)
    }

    /// Whether a changed target should animate: only while the reveal count-up is still running,
    /// so a later server resync never replays the animation.
    static func shouldAnimateRetarget(since revealStart: Date?, now: Date = Date(), window: TimeInterval = RevealCounter.window) -> Bool {
        guard let revealStart else { return false }
        return now.timeIntervalSince(revealStart) < window
    }
}

/// A count or percentage that rises from 0 when `isRevealed` flips on, and simply
/// shows its value when it appears already revealed. Reduce Motion skips the rise;
/// hiding the result again snaps back and cancels any running animation.
/// VoiceOver always reads the final value.
struct RevealCounter: View {
    enum Style { case count, percent }

    static let duration: Double = 3.0
    static let window: TimeInterval = duration + 0.6

    let target: Int
    let isRevealed: Bool
    var style: Style = .count
    /// Staggers one counter behind the previous one.
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0
    @State private var revealStart: Date?

    var body: some View {
        RisingNumberText(value: shown, isPercent: style == .percent)
            .accessibilityLabel(style == .percent ? "\(target)%" : "\(target)")
            .onAppear { shown = Double(target) }
            .onChange(of: isRevealed) { _, nowRevealed in nowRevealed ? rise(from: 0) : snap() }
            .onChange(of: target) { _, _ in retarget() }
    }

    private func rise(from start: Double) {
        guard !reduceMotion else { return snap() }
        revealStart = Date()
        withTransaction(Transaction(animation: nil)) { shown = start }
        withAnimation(.easeOut(duration: Self.duration).delay(delay)) { shown = Double(target) }
    }

    private func retarget() {
        guard isRevealed, !reduceMotion, VoteReveal.shouldAnimateRetarget(since: revealStart) else { return snap() }
        withAnimation(.easeOut(duration: Self.duration)) { shown = Double(target) }
    }

    /// Shows the final value at once, replacing any in-flight animation.
    private func snap() {
        revealStart = nil
        withTransaction(Transaction(animation: nil)) { shown = Double(target) }
    }
}

private struct RisingNumberText: View, Animatable {
    var value: Double
    let isPercent: Bool

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(isPercent ? "\(Int(value.rounded()))%" : "\(Int(value.rounded()))").monospacedDigit()
    }
}

/// Confetti overlay state: a fresh id per burst, cleared when it ends or is cancelled.
@MainActor
final class CelebrationState: ObservableObject {
    @Published private(set) var burstId: UUID?
    private var clearTask: Task<Void, Never>?

    func celebrate() {
        let id = UUID()
        burstId = id
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ConfettiBurst.duration))
            guard !Task.isCancelled, self?.burstId == id else { return }
            self?.burstId = nil
        }
    }

    func cancel() {
        clearTask?.cancel()
        burstId = nil
    }
}
