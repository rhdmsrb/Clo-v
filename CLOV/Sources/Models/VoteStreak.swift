import Foundation

/// How many looks the user has voted on today and for how many days in a row.
struct VoteStreak: Codable, Equatable {
    var days = 0
    var votesToday = 0
    var lastVoteDay: Date?

    /// The streak after a vote cast at `date`; the receiver is unchanged.
    func recording(on date: Date, calendar: Calendar = .current) -> VoteStreak {
        guard let lastVoteDay else { return VoteStreak(days: 1, votesToday: 1, lastVoteDay: date) }
        if calendar.isDate(lastVoteDay, inSameDayAs: date) {
            return VoteStreak(days: max(days, 1), votesToday: votesToday + 1, lastVoteDay: date)
        }
        let isNextDay = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastVoteDay),
                                                to: calendar.startOfDay(for: date)).day == 1
        return VoteStreak(days: isNextDay ? days + 1 : 1, votesToday: 1, lastVoteDay: date)
    }

    /// The streak after a vote is cancelled: today's count drops by one, the day streak is kept.
    func unrecording() -> VoteStreak {
        VoteStreak(days: days, votesToday: max(votesToday - 1, 0), lastVoteDay: lastVoteDay)
    }

    /// e.g. "Vote 3 today · 4-day streak"; nil when the last vote wasn't today.
    func summary(on date: Date = .now, calendar: Calendar = .current) -> String? {
        guard let lastVoteDay, calendar.isDate(lastVoteDay, inSameDayAs: date), votesToday > 0 else { return nil }
        let base = "Vote \(votesToday) today"
        return days >= 2 ? "\(base) · \(days)-day streak" : base
    }
}

/// Persists each user's `VoteStreak` on this device.
enum VoteStreakStore {
    private static func key(for userId: UUID) -> String { "clov.voteStreak.v1.\(userId.uuidString)" }

    static func load(for userId: UUID) -> VoteStreak {
        guard let data = UserDefaults.standard.data(forKey: key(for: userId)),
              let streak = try? JSONDecoder().decode(VoteStreak.self, from: data) else { return VoteStreak() }
        return streak
    }

    @discardableResult
    static func recordVote(for userId: UUID, on date: Date = .now) -> VoteStreak {
        let updated = load(for: userId).recording(on: date)
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(updated), forKey: key(for: userId))
        } catch {
            Log.app.error("Saving vote streak failed: \(error.localizedDescription)")
        }
        return updated
    }

    @discardableResult
    static func unrecordVote(for userId: UUID) -> VoteStreak {
        let updated = load(for: userId).unrecording()
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(updated), forKey: key(for: userId))
        } catch {
            Log.app.error("Saving vote streak failed: \(error.localizedDescription)")
        }
        return updated
    }
}
