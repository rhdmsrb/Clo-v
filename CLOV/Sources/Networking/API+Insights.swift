import Foundation
import Supabase

extension API {
    // MARK: - Style insights

    static func fetchWeeklyStyleReport(userId: UUID) async throws -> WeeklyStyleReport {
#if DEBUG
        if SampleData.isActive { return SampleData.weeklyReport }
#endif
        struct ActivityRow: Decodable {
            let createdAt: Date
            let occasion: String?
        }

        let calendar = Calendar.current
        let now = Date()
        let weekStart = calendar.date(byAdding: .day, value: -6, to: now) ?? now
        let historyStart = calendar.date(byAdding: .day, value: -60, to: now) ?? now
        let since = ISO8601DateFormatter().string(from: historyStart)

        async let votesTask: [ActivityRow] = client
            .from("fit_check_votes")
            .select("created_at")
            .eq("voter_id", value: userId)
            .gte("created_at", value: since)
            .execute().value
        async let postsTask: [ActivityRow] = client
            .from("fit_checks")
            .select("created_at, occasion")
            .eq("creator_id", value: userId)
            .neq("status", value: "draft")
            .gte("created_at", value: since)
            .execute().value
        async let commentsTask: [ActivityRow] = client
            .from("fit_check_comments")
            .select("created_at")
            .eq("commenter_id", value: userId)
            .gte("created_at", value: since)
            .execute().value
        async let wardrobeTask: [ActivityRow] = client
            .from("wardrobe_items")
            .select("created_at")
            .eq("owner_id", value: userId)
            .gte("created_at", value: since)
            .execute().value

        let (votes, posts, comments, wardrobe) = try await (votesTask, postsTask, commentsTask, wardrobeTask)
        let weekStartDay = calendar.startOfDay(for: weekStart)
        let inWeek: (ActivityRow) -> Bool = { row in row.createdAt >= weekStartDay }
        let activeDates = (votes + posts + comments + wardrobe).map { calendar.startOfDay(for: $0.createdAt) }
        let activeDateSet = Set(activeDates)

        var streak = 0
        var cursor = calendar.startOfDay(for: now)
        if !activeDateSet.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while activeDateSet.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        let occasionCounts = posts.filter(inWeek).compactMap(\.occasion).reduce(into: [:]) { counts, occasion in
            counts[occasion, default: 0] += 1
        }
        let topOccasion = occasionCounts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key

        return WeeklyStyleReport(
            votesCast: votes.filter(inWeek).count,
            fitChecksPosted: posts.filter(inWeek).count,
            commentsWritten: comments.filter(inWeek).count,
            wardrobePiecesAdded: wardrobe.filter(inWeek).count,
            currentStreak: streak,
            topOccasion: topOccasion
        )
    }

    static func fetchFeedSignalScores(userId: UUID) async throws -> [UUID: Int] {
#if DEBUG
        if SampleData.isActive { return SampleData.signalScores }
#endif
        struct Row: Decodable {
            let fitCheckId: UUID
            let event: String
        }
        let rows: [Row] = try await client.from("feed_events")
            .select("fit_check_id, event")
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(500)
            .execute().value
        let weights = [
            "impression": -1,
            "open_detail": 3,
            "vote": 6,
            "save": 4,
            "share": 5,
            "follow": 2,
            "unfollow": -2,
            "not_interested": -8
        ]
        return rows.reduce(into: [:]) { scores, row in
            scores[row.fitCheckId, default: 0] += weights[row.event, default: 0]
        }
    }
}
