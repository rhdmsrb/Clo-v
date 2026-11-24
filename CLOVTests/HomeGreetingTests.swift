import Foundation
import Testing
@testable import CLOV

@Suite("Home feed prompt")
struct HomeGreetingTests {
    private typealias Moment = HomeGreeting.Moment

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-11 calendar: the 23rd is a Monday, the 27th a Friday, the 29th a Sunday.
    private func date(month: Int = 11, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// Every combination of part of day, weekday and season.
    private static let allMoments: [Moment] = HomeGreeting.DayPart.allCases.flatMap { part in
        (1...7).flatMap { weekday in
            HomeGreeting.Season.allCases.map { Moment(dayPart: part, weekday: weekday, season: $0) }
        }
    }

    private static var allTemplates: Set<String> { Set(allMoments.flatMap(HomeGreeting.prompts(for:))) }

    private func prompts(_ moment: Moment, nickname: String? = "danny") -> [String] {
        HomeGreeting.prompts(for: moment).map { HomeGreeting.fill($0, nickname: nickname) }
    }

    // MARK: Reading the moment

    @Test("The hour maps to its part of the day", arguments: [
        (6, HomeGreeting.DayPart.earlyMorning), (10, .morning), (13, .lunch), (15, .afternoon),
        (19, .evening), (22, .night), (2, .lateNight),
    ])
    func dayPart(hour: Int, part: HomeGreeting.DayPart) {
        #expect(HomeGreeting.dayPart(hour: hour) == part)
    }

    @Test("The month maps to its season", arguments: [
        (1, HomeGreeting.Season.winter), (4, .spring), (7, .summer), (10, .autumn), (12, .winter),
    ])
    func season(month: Int, season: HomeGreeting.Season) {
        #expect(HomeGreeting.season(month: month) == season)
    }

    // MARK: Fitting the situation

    @Test("Monday mornings can mention Monday")
    func mondayMorning() {
        let text = HomeGreeting.text(date: date(day: 23, hour: 7), nickname: "danny", calendar: calendar)
        #expect(prompts(HomeGreeting.moment(date: date(day: 23, hour: 7), calendar: calendar)).contains(text))
        #expect(prompts(Moment(dayPart: .morning, weekday: Moment.monday, season: .autumn))
            .contains { $0.contains("Monday") })
    }

    @Test("Friday evenings can mention Friday; other evenings never do")
    func fridayEvening() {
        #expect(prompts(Moment(dayPart: .evening, weekday: Moment.friday, season: .autumn))
            .contains { $0.contains("Friday") })
        for weekday in (1...7) where weekday != Moment.friday {
            #expect(!prompts(Moment(dayPart: .evening, weekday: weekday, season: .autumn))
                .contains { $0.contains("Friday") })
        }
    }

    @Test("Sunday evenings look ahead to Monday")
    func sundayEvening() {
        #expect(prompts(Moment(dayPart: .evening, weekday: Moment.sunday, season: .winter))
            .contains { $0.contains("Monday") })
    }

    @Test("Weekends never talk about work, workdays never talk about the weekend's brunch")
    func weekendVersusWorkday() {
        for moment in Self.allMoments {
            let texts = prompts(moment)
            if moment.isWeekend {
                #expect(!texts.contains { $0.contains("work") || $0.contains("Desk") }, "\(moment)")
            } else {
                #expect(!texts.contains { $0.contains("Brunch") || $0.contains("weekend") } || moment.weekday == Moment.friday,
                        "\(moment)")
            }
        }
    }

    @Test("Season prompts show only on mornings, and match the season")
    func seasonPrompts() {
        let winterMorning = prompts(Moment(dayPart: .earlyMorning, weekday: 3, season: .winter))
        #expect(winterMorning.contains { $0.contains("Coat") || $0.contains("Cold") })
        #expect(!winterMorning.contains { $0.contains("Linen") })
        let winterEvening = prompts(Moment(dayPart: .evening, weekday: 3, season: .winter))
        #expect(!winterEvening.contains { $0.contains("Coat") })
    }

    @Test("Every moment offers several prompts", arguments: allMoments)
    func enoughVariety(moment: HomeGreeting.Moment) {
        #expect(HomeGreeting.prompts(for: moment).count >= 3)
    }

    @Test("There are plenty of distinct prompts overall")
    func overallVariety() {
        #expect(Self.allTemplates.count >= 60)
    }

    // MARK: Picking

    @Test("The prompt stays the same within a part of the day and varies across days")
    func stableWithinADayPart() {
        let early = HomeGreeting.text(date: date(day: 24, hour: 14), nickname: "danny", calendar: calendar)
        let late = HomeGreeting.text(date: date(day: 24, hour: 16), nickname: "danny", calendar: calendar)
        #expect(early == late)
        let tuesdays = [3, 10, 17, 24].map { HomeGreeting.text(date: date(day: $0, hour: 15), nickname: nil, calendar: calendar) }
        #expect(Set(tuesdays).count > 1, "a month of Tuesday afternoons should not repeat one prompt")
    }

    // MARK: The name

    @Test("Each prompt holds the name once, right before punctuation")
    func placeholderShape() {
        for template in Self.allTemplates {
            #expect(template.components(separatedBy: HomeGreeting.namePlaceholder).count == 2, "\(template)")
            #expect(template.range(of: #", \{name\}[?.!]"#, options: .regularExpression) != nil, "\(template)")
        }
    }

    @Test("Without a nickname the prompt reads cleanly", arguments: [nil, "", "   "])
    func missingName(nickname: String?) {
        for template in Self.allTemplates {
            let text = HomeGreeting.fill(template, nickname: nickname)
            #expect(!text.contains("{name}") && !text.contains(" ,") && !text.contains("  "), "\(text)")
        }
    }

    @Test("With a nickname every prompt names the viewer, trimmed")
    func namesTheViewer() {
        for template in Self.allTemplates {
            #expect(HomeGreeting.fill(template, nickname: " danny ").contains(", danny"), "\(template)")
        }
    }
}
