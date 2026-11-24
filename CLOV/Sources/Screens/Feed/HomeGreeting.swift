import Foundation

/// The outfit prompt under the Home wordmark ("What are you wearing today, maya?"), unit tested.
///
/// The pool fits the moment: the part of the day, workday or weekend, a few days with a
/// character of their own (Monday morning, Friday night, Sunday evening), and the season
/// on mornings, when people are getting dressed. One prompt is picked per day, so it stays
/// put within a part of the day instead of changing on every visit.
enum HomeGreeting {
    enum DayPart: CaseIterable {
        case earlyMorning, morning, lunch, afternoon, evening, night, lateNight
    }

    enum Season: CaseIterable {
        case spring, summer, autumn, winter
    }

    /// Where the viewer is in their day and year.
    struct Moment: Equatable {
        let dayPart: DayPart
        /// Gregorian weekday, 1 = Sunday ... 7 = Saturday.
        let weekday: Int
        let season: Season

        var isWeekend: Bool { weekday == Self.sunday || weekday == Self.saturday }

        static let sunday = 1, monday = 2, friday = 6, saturday = 7
    }

    /// Stands in for the nickname. Always written as ", {name}" right before a ? . or !,
    /// so it drops out cleanly when there is no nickname.
    static let namePlaceholder = "{name}"

    // MARK: Picking

    static func text(date: Date, nickname: String?, calendar: Calendar = .current) -> String {
        let options = prompts(for: moment(date: date, calendar: calendar))
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return fill(options[day % options.count], nickname: nickname)
    }

    static func moment(date: Date, calendar: Calendar = .current) -> Moment {
        Moment(dayPart: dayPart(hour: calendar.component(.hour, from: date)),
               weekday: calendar.component(.weekday, from: date),
               season: season(month: calendar.component(.month, from: date)))
    }

    static func dayPart(hour: Int) -> DayPart {
        switch hour {
        case 5..<9: .earlyMorning
        case 9..<12: .morning
        case 12..<14: .lunch
        case 14..<17: .afternoon
        case 17..<21: .evening
        case 21..<24: .night
        default: .lateNight
        }
    }

    /// Northern-hemisphere seasons by month (1...12).
    static func season(month: Int) -> Season {
        switch month {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
    }

    /// Every prompt that fits the moment; never empty.
    static func prompts(for moment: Moment) -> [String] {
        let base = moment.isWeekend ? weekendPrompts(moment.dayPart) : workdayPrompts(moment.dayPart)
        let isDressingTime = moment.dayPart == .earlyMorning || moment.dayPart == .morning
        return base + specialDayPrompts(moment) + (isDressingTime ? seasonPrompts(moment.season) : [])
    }

    /// Puts the trimmed nickname in place of the placeholder, or drops ", {name}" when there is none.
    static func fill(_ template: String, nickname: String?) -> String {
        let name = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty
            ? template.replacingOccurrences(of: ", \(namePlaceholder)", with: "")
            : template.replacingOccurrences(of: namePlaceholder, with: name)
    }
}

// MARK: - Prompts

extension HomeGreeting {
    static func workdayPrompts(_ part: DayPart) -> [String] {
        switch part {
        case .earlyMorning: [
            "What are you wearing today, {name}?",
            "Two outfits on the bed, {name}? Post them both.",
            "Early start, {name}? Let your circle pick the look.",
            "Commute-ready, {name}? Show the fit.",
            "Can’t decide what to wear, {name}? Ask your circle.",
        ]
        case .morning: [
            "What did you end up wearing, {name}?",
            "Desk fit or meeting fit, {name}?",
            "Already second-guessing the outfit, {name}?",
            "Which look are you leaning toward today, {name}?",
            "Plans after work, {name}? Line up the look now.",
        ]
        case .lunch: [
            "Lunch break, {name}? Vote on a friend’s fit.",
            "Midday outfit check, {name}?",
            "Grabbing lunch, {name}? Snap today’s fit.",
            "Still happy with this morning’s pick, {name}?",
        ]
        case .afternoon: [
            "Plans after work, {name}? Post the options.",
            "Changing for tonight, {name}?",
            "Afternoon slump, {name}? Help a friend pick a look.",
            "Thinking about tonight’s look, {name}?",
            "Is the outfit still working, {name}?",
        ]
        case .evening: [
            "Going out tonight, {name}? What’s the fit?",
            "Dinner plans, {name}? Let your circle choose.",
            "What’s the look tonight, {name}?",
            "Heading out, {name}? Post a quick Fit-Check.",
            "Staying in or dressing up, {name}?",
        ]
        case .night: [
            "Planning tomorrow’s outfit, {name}?",
            "Lay out tomorrow’s fit, {name}. Your circle can vote by morning.",
            "Winding down, {name}? See how today’s votes went.",
            "Big day tomorrow, {name}? Sort the outfit tonight.",
        ]
        case .lateNight: [
            "Up late, {name}? Plan tomorrow’s fit.",
            "Still up, {name}? Help a friend pick a look.",
            "Can’t sleep, {name}? Scroll some fits.",
            "Late-night outfit planning, {name}?",
        ]
        }
    }

    static func weekendPrompts(_ part: DayPart) -> [String] {
        switch part {
        case .earlyMorning: [
            "Up early on a weekend, {name}? What’s the plan?",
            "Slow start, {name}? No rush on the fit.",
            "Market run or a lie-in, {name}?",
        ]
        case .morning: [
            "Weekend plans, {name}? What’s the fit?",
            "Brunch fit or comfy fit, {name}?",
            "Dressing for the weekend, {name}?",
            "Off duty today, {name}? Show the look.",
        ]
        case .lunch: [
            "Brunch running long, {name}? Snap the fit.",
            "What’s the weekend lunch look, {name}?",
            "Out and about, {name}? Post today’s fit.",
        ]
        case .afternoon: [
            "Weekend wander, {name}? What are you wearing?",
            "Errands or plans, {name}? Show the fit.",
            "Getting ready for tonight already, {name}?",
        ]
        case .evening: [
            "Big night out, {name}? Let your circle pick.",
            "Weekend dinner plans, {name}? What’s the look?",
            "Party fit or low-key fit, {name}?",
            "Getting ready to head out, {name}?",
        ]
        case .night: [
            "Still out, {name}? Show off the fit.",
            "Night’s not over, {name}! Post the look.",
            "Home already, {name}? See how your look did.",
        ]
        case .lateNight: [
            "Big night, {name}? Vote on your friends’ fits.",
            "Still up, {name}? Help a friend pick a look.",
            "Can’t sleep, {name}? Scroll some fits.",
        ]
        }
    }

    /// Extra prompts for days with a character of their own.
    static func specialDayPrompts(_ moment: Moment) -> [String] {
        switch (moment.weekday, moment.dayPart) {
        case (Moment.monday, .earlyMorning), (Moment.monday, .morning): [
            "Monday again, {name}. What’s the fit?",
            "Start the week strong, {name}. Which look?",
        ]
        case (Moment.friday, .afternoon), (Moment.friday, .evening), (Moment.friday, .night): [
            "Friday at last, {name}! What are you wearing out?",
            "Friday night fit, {name}?",
            "The weekend starts now, {name}. Dress for it.",
        ]
        case (Moment.sunday, .evening), (Moment.sunday, .night): [
            "Sunday reset, {name}? Plan Monday’s outfit.",
            "New week tomorrow, {name}. Sort Monday’s fit tonight.",
        ]
        default: []
        }
    }

    /// Weather-of-the-season prompts, shown on mornings while people get dressed.
    static func seasonPrompts(_ season: Season) -> [String] {
        switch season {
        case .spring: [
            "Jacket or no jacket today, {name}?",
            "Spring layers, {name}? Show the look.",
        ]
        case .summer: [
            "Hot one today, {name}? Keep the fit light.",
            "Linen or denim today, {name}?",
        ]
        case .autumn: [
            "Sweater weather, {name}? Show the knit.",
            "Boots out yet, {name}?",
        ]
        case .winter: [
            "Cold one out, {name}. Layers or the big coat?",
            "Coat season, {name}. Which one today?",
        ]
        }
    }
}
