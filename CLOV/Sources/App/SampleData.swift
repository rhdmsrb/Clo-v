import Foundation
import Supabase

#if DEBUG
/// Canned, fully offline data for walking the UI in the simulator without an
/// account or backend. Active only in DEBUG builds launched with
/// `--uiTestSampleData`; every API read short-circuits to these values and
/// every write is a no-op, so no request ever reaches Supabase.
enum SampleData {
    static let launchArgument = "--uiTestSampleData"
    static let isActive = ProcessInfo.processInfo.arguments.contains(launchArgument)

    /// Host served by `SampleImageURLProtocol`; `.invalid` can never resolve,
    /// so a missed interception fails fast instead of reaching the internet.
    static let imageHost = "sample.clov.invalid"

    private static let uuidTemplate = "00000000-0000-4000-8000-%012d"
    private static let hoursToSeconds: TimeInterval = 3600

    static func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: uuidTemplate, number)) ?? UUID()
    }

    static func hours(_ value: Double) -> TimeInterval { value * hoursToSeconds }

    static func imageURL(kind: String, number: Int) -> String {
        "https://\(imageHost)/\(kind)/\(number).jpg"
    }

    // MARK: - People

    struct Person {
        let number: Int
        let nickname: String
        let accountCode: String
        let hasAvatar: Bool

        var id: UUID { SampleData.uuid(number) }
        var avatarUrl: String? { hasAvatar ? SampleData.imageURL(kind: "avatar", number: number) : nil }
        var info: AuthorInfo { AuthorInfo(nickname: nickname, avatarUrl: avatarUrl) }
        var withId: AuthorInfoWithId {
            AuthorInfoWithId(id: id, nickname: nickname, accountCode: accountCode, avatarUrl: avatarUrl)
        }
    }

    static let me = Person(number: 1, nickname: "sampleuser", accountCode: "SAMPLE01", hasAvatar: true)
    static let maya = Person(number: 2, nickname: "maya.chen", accountCode: "MAYA0002", hasAvatar: true)
    static let jun = Person(number: 3, nickname: "junwearsthings", accountCode: "JUN00003", hasAvatar: false)
    static let sora = Person(number: 4, nickname: "sora", accountCode: "SORA0004", hasAvatar: true)
    static let alex = Person(number: 5, nickname: "alex_the_extremely_long_nickname", accountCode: "ALEX0005", hasAvatar: false)
    static let riley = Person(number: 6, nickname: "riley", accountCode: "RILEY006", hasAvatar: false)

    static let everyone: [Person] = [me, maya, jun, sora, alex, riley]
    static let others: [Person] = [maya, jun, sora, alex, riley]

    static func person(id: UUID) -> Person? { everyone.first { $0.id == id } }

    // MARK: - Session and profile

    static var profile: Profile {
        Profile(id: me.id, nickname: me.nickname, stylePreferences: ["Streetwear", "Minimal"],
                avatarUrl: me.avatarUrl, createdAt: Date().addingTimeInterval(-hours(24 * 30)))
    }

    static var session: Session {
        let now = Date()
        let user = User(
            id: me.id, appMetadata: [:], userMetadata: [:], aud: "authenticated",
            email: "sample@clov.test", createdAt: now, updatedAt: now
        )
        return Session(
            accessToken: "sample-access-token", tokenType: "bearer", expiresIn: hours(24 * 365),
            expiresAt: now.addingTimeInterval(hours(24 * 365)).timeIntervalSince1970,
            refreshToken: "sample-refresh-token", user: user
        )
    }

    static var weeklyReport: WeeklyStyleReport {
        WeeklyStyleReport(votesCast: 12, fitChecksPosted: 3, commentsWritten: 5,
                          wardrobePiecesAdded: 2, currentStreak: 4, topOccasion: "Casual")
    }

    // MARK: - Social graph

    static let friendIDs: Set<UUID> = [maya.id, sora.id]
    static let followingIDs: Set<UUID> = [maya.id, jun.id]
    static let followerIDs: Set<UUID> = [maya.id, jun.id, alex.id]
    static let signalScores: [UUID: Int] = [uuid(1_001): 6, uuid(1_002): -1, uuid(1_004): 3]

    static func friendRequests(incoming: Bool) -> [FriendRequestDTO] {
        incoming
            ? [FriendRequestDTO(id: uuid(2_001), requesterId: jun.id, addresseeId: me.id, status: "pending")]
            : [FriendRequestDTO(id: uuid(2_002), requesterId: me.id, addresseeId: riley.id, status: "pending")]
    }

    static var friendships: [FriendshipDTO] {
        friendIDs.map { friend in
            let ordered = [me.id.uuidString, friend.uuidString].sorted()
            return FriendshipDTO(userLow: UUID(uuidString: ordered[0]) ?? me.id,
                                 userHigh: UUID(uuidString: ordered[1]) ?? friend)
        }
    }

    static func profiles(ids: [UUID]) -> [AuthorInfoWithId] {
        ids.compactMap { person(id: $0)?.withId }
    }

    static func searchProfiles(query: String, excluding userId: UUID) -> [AuthorInfoWithId] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return [] }
        return others.filter { $0.id != userId }
            .filter { $0.nickname.lowercased().contains(term) || $0.accountCode.lowercased().contains(term) }
            .map(\.withId)
    }

    static func mutualFriendCounts(userIds: [UUID]) -> [MutualFriendCountDTO] {
        userIds.enumerated().map { MutualFriendCountDTO(userId: $0.element, mutualCount: $0.offset % 3) }
    }
}
#endif
