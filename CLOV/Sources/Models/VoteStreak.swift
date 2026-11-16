import Foundation

/// How many looks the user has voted on today and for how many days in a row.
struct VoteStreak: Codable, Equatable {
    var days = 0
    var votesToday = 0
    var lastVoteDay: Date?
    /// The streak as it was before today's first vote, so taking that vote back can take
    /// today out of the streak too. Nil in data saved before this existed.
    var daysBeforeToday: Int?
    var lastVoteDayBeforeToday: Date?

    /// The streak after a vote cast at `date`; the receiver is unchanged.
    func recording(on date: Date, calendar: Calendar = .current) -> VoteStreak {
        guard let lastVoteDay else {
            return VoteStreak(days: 1, votesToday: 1, lastVoteDay: date, daysBeforeToday: 0, lastVoteDayBeforeToday: nil)
        }
        if calendar.isDate(lastVoteDay, inSameDayAs: date) {
            var next = self
            next.days = max(days, 1)
            next.votesToday += 1
            next.lastVoteDay = date
            return next
        }
        let isNextDay = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastVoteDay),
                                                to: calendar.startOfDay(for: date)).day == 1
        return VoteStreak(days: isNextDay ? days + 1 : 1, votesToday: 1, lastVoteDay: date,
                          daysBeforeToday: days, lastVoteDayBeforeToday: lastVoteDay)
    }

    /// The streak after a vote cast on `date` is cancelled. Taking back one of several votes
    /// only lowers today's count; taking back the day's only vote also removes today from
    /// the streak. A vote from an earlier day is left alone, as the day has already passed.
    func unrecording(on date: Date = .now, calendar: Calendar = .current) -> VoteStreak {
        guard let lastVoteDay, votesToday > 0, calendar.isDate(lastVoteDay, inSameDayAs: date) else { return self }
        if votesToday > 1 {
            var next = self
            next.votesToday -= 1
            return next
        }
        guard let daysBeforeToday else {
            return VoteStreak(days: days, votesToday: 0, lastVoteDay: lastVoteDay)
        }
        return VoteStreak(days: daysBeforeToday, votesToday: 0, lastVoteDay: lastVoteDayBeforeToday)
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
