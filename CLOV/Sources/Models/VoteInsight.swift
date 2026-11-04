import Foundation

/// Plain-language read on how a voter's pick compares with everyone else's.
enum VoteInsight {
    private static let minVotesForComparison = 3
    private static let landslidePercent = 70
    /// Share a look would get if votes split evenly, scaled down for "close call".
    private static let closeCallFactor = 0.75

    static func message(percent: Int, isLeading: Bool, total: Int, optionCount: Int) -> String {
        guard total >= minVotesForComparison else {
            return "You're one of the first to weigh in. Check back to see who agrees."
        }
        if isLeading {
            return percent >= landslidePercent
                ? "Landslide — \(percent)% of voters picked your look."
                : "You're with the majority · \(percent)% agree."
        }
        let evenShare = 100.0 / Double(max(optionCount, 2))
        return Double(percent) >= evenShare * closeCallFactor
            ? "Close call — \(percent)% picked it too."
            : "Bold pick — only \(percent)% agree."
    }
}
