import XCTest
@testable import CLOV

final class VoteInsightTests: XCTestCase {
    func testFewVotesInvitesVoterToCheckBack() {
        let text = VoteInsight.message(percent: 100, isLeading: true, total: 2, optionCount: 2)
        XCTAssertTrue(text.contains("first"))
    }

    func testLandslideWhenLeadingBySeventyPercentOrMore() {
        XCTAssertEqual(VoteInsight.message(percent: 82, isLeading: true, total: 20, optionCount: 2),
                       "Landslide — 82% of voters picked your look.")
    }

    func testMajorityWhenLeadingNarrowly() {
        XCTAssertEqual(VoteInsight.message(percent: 58, isLeading: true, total: 20, optionCount: 2),
                       "You're with the majority · 58% agree.")
    }

    func testCloseCallWhenTrailingButNearAverageShare() {
        XCTAssertEqual(VoteInsight.message(percent: 42, isLeading: false, total: 20, optionCount: 2),
                       "Close call — 42% picked it too.")
    }

    func testBoldPickWhenWellBelowAverageShare() {
        XCTAssertEqual(VoteInsight.message(percent: 15, isLeading: false, total: 20, optionCount: 2),
                       "Bold pick — only 15% agree.")
    }

    func testFourLookVoteTreatsTwentyPercentAsCloseCall() {
        XCTAssertEqual(VoteInsight.message(percent: 22, isLeading: false, total: 20, optionCount: 4),
                       "Close call — 22% picked it too.")
        XCTAssertTrue(VoteInsight.message(percent: 10, isLeading: false, total: 20, optionCount: 4).hasPrefix("Bold pick"))
    }
}

final class VoteStreakTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: Date(timeIntervalSince1970: 1_800_000_000))!
    }

    func testFirstVoteStartsStreakOfOne() {
        let streak = VoteStreak().recording(on: day(0), calendar: calendar)
        XCTAssertEqual(streak.votesToday, 1)
        XCTAssertEqual(streak.days, 1)
    }

    func testSameDayVotesCountUpWithoutChangingStreak() {
        let streak = VoteStreak().recording(on: day(0), calendar: calendar).recording(on: day(0), calendar: calendar)
        XCTAssertEqual(streak.votesToday, 2)
        XCTAssertEqual(streak.days, 1)
    }

    func testNextDayExtendsStreakAndResetsDailyCount() {
        let streak = VoteStreak().recording(on: day(0), calendar: calendar)
            .recording(on: day(0), calendar: calendar).recording(on: day(1), calendar: calendar)
        XCTAssertEqual(streak.votesToday, 1)
        XCTAssertEqual(streak.days, 2)
    }

    func testCancellingOneOfTwoVotesTodayKeepsTheDayStreak() {
        let streak = VoteStreak().recording(on: day(0), calendar: calendar)
            .recording(on: day(1), calendar: calendar).recording(on: day(1), calendar: calendar)
            .unrecording(on: day(1), calendar: calendar)
        XCTAssertEqual(streak.votesToday, 1)
        XCTAssertEqual(streak.days, 2)
    }

    /// A vote that is taken back must not leave today's streak credit behind.
    func testCancellingTheOnlyVoteTodayTakesTodayOutOfTheStreak() {
        let streak = VoteStreak().recording(on: day(0), calendar: calendar)
            .recording(on: day(1), calendar: calendar).unrecording(on: day(1), calendar: calendar)
        XCTAssertEqual(streak.votesToday, 0)
        XCTAssertEqual(streak.days, 1)
        XCTAssertEqual(streak.lastVoteDay, day(0))
        XCTAssertNil(streak.summary(on: day(1), calendar: calendar))
    }

    func testCancellingTheVeryFirstVoteMakesTheUserAFirstTimeVoterAgain() {
        let streak = VoteStreak().recording(on: day(0), calendar: calendar).unrecording(on: day(0), calendar: calendar)
        XCTAssertEqual(streak, VoteStreak())
    }

    func testVotingAgainAfterCancellingGivesTheSameStreakAsNeverCancelling() {
        let direct = VoteStreak().recording(on: day(0), calendar: calendar).recording(on: day(1), calendar: calendar)
        let afterUndo = VoteStreak().recording(on: day(0), calendar: calendar).recording(on: day(1), calendar: calendar)
            .unrecording(on: day(1), calendar: calendar).recording(on: day(1), calendar: calendar)
        XCTAssertEqual(afterUndo.days, direct.days)
        XCTAssertEqual(afterUndo.votesToday, direct.votesToday)
    }

    func testCancellingAnEarlierDaysVoteDoesNotTouchToday() {
        let streak = VoteStreak().recording(on: day(0), calendar: calendar)
        XCTAssertEqual(streak.unrecording(on: day(1), calendar: calendar), streak)
    }

    func testCancellingNeverGoesBelowZero() {
        XCTAssertEqual(VoteStreak().unrecording().votesToday, 0)
    }

    func testStreakSavedBeforeThisChangeStillLoadsAndKeepsItsDays() throws {
        let legacy = VoteStreak(days: 3, votesToday: 1, lastVoteDay: day(1))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        json.removeValue(forKey: "daysBeforeToday")
        json.removeValue(forKey: "lastVoteDayBeforeToday")
        let decoded = try JSONDecoder().decode(VoteStreak.self, from: JSONSerialization.data(withJSONObject: json))
        // No snapshot to restore, so cancelling keeps the days as it always did.
        XCTAssertEqual(decoded.unrecording(on: day(1), calendar: calendar).days, 3)
    }

    func testStreakSurvivesEncodingWithItsSnapshot() throws {
        let streak = VoteStreak().recording(on: day(0), calendar: calendar).recording(on: day(1), calendar: calendar)
        let decoded = try JSONDecoder().decode(VoteStreak.self, from: JSONEncoder().encode(streak))
        XCTAssertEqual(decoded, streak)
    }

    func testMissedDayResetsStreak() {
        let streak = VoteStreak().recording(on: day(0), calendar: calendar)
            .recording(on: day(1), calendar: calendar).recording(on: day(3), calendar: calendar)
        XCTAssertEqual(streak.days, 1)
        XCTAssertEqual(streak.votesToday, 1)
    }

    func testSummaryMentionsStreakOnlyFromTwoDays() {
        XCTAssertEqual(VoteStreak(days: 1, votesToday: 1, lastVoteDay: day(0)).summary(on: day(0), calendar: calendar), "Vote 1 today")
        XCTAssertEqual(VoteStreak(days: 4, votesToday: 3, lastVoteDay: day(0)).summary(on: day(0), calendar: calendar), "Vote 3 today · 4-day streak")
    }

    func testStaleStreakIsNotShown() {
        let stale = VoteStreak(days: 5, votesToday: 2, lastVoteDay: day(0))
        XCTAssertNil(stale.summary(on: day(3), calendar: calendar))
    }
}
