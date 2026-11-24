import Foundation

/// Pure state machine for the press-and-hold vote gesture.
struct HoldProgress: Equatable {
    enum Phase: Equatable { case idle, holding, completed }

    /// Default seconds the finger must stay down.
    static let duration: TimeInterval = 0.6
    /// Progress fractions at which a light haptic tick fires.
    static let hapticMilestones: [Double] = [0.33, 0.66]

    let phase: Phase
    /// 0...1
    let progress: Double

    static let idle = HoldProgress(phase: .idle, progress: 0)

    func begin() -> HoldProgress {
        phase == .completed ? self : HoldProgress(phase: .holding, progress: 0)
    }

    /// Advance given seconds elapsed since `begin`, for a hold lasting `duration`.
    /// Never completes by itself; completion is confirmed by the system long-press via `complete()`.
    func tick(elapsed: TimeInterval, duration: TimeInterval = Self.duration) -> HoldProgress {
        guard phase == .holding, duration > 0 else { return self }
        let fraction = min(max(elapsed / duration, 0), 1)
        return HoldProgress(phase: .holding, progress: max(progress, fraction))
    }

    func complete() -> HoldProgress {
        guard phase == .holding else { return self }
        return HoldProgress(phase: .completed, progress: 1)
    }

    /// Early lift, slide away, or interruption.
    func cancel() -> HoldProgress {
        phase == .completed ? self : .idle
    }

    /// Back to idle after the completion burst has played.
    func reset() -> HoldProgress { .idle }

    /// Milestones crossed going from `previous` to this state.
    func crossedMilestones(since previous: HoldProgress) -> Int {
        Self.hapticMilestones.filter { previous.progress < $0 && progress >= $0 }.count
    }
}
