import Foundation

public enum SundayCalendar {
    public static func isSunday(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.weekday, from: date) == 1
    }

    /// Start of the most recent Sunday on or before `date`, keeping the time of
    /// day of `date` so a dinner logged now sorts sensibly.
    public static func mostRecentSunday(onOrBefore date: Date, calendar: Calendar = .current) -> Date {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: date) ?? date
    }

    /// How many Sundays in a row (ending this Sunday, or last Sunday if this
    /// one hasn't been logged yet) have at least one dinner.
    public static func streak(mealDates: [Date], now: Date = .now, calendar: Calendar = .current) -> Int {
        let sundays = Set(mealDates.filter { isSunday($0, calendar: calendar) }.map { calendar.startOfDay(for: $0) })
        guard !sundays.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: mostRecentSunday(onOrBefore: now, calendar: calendar))
        // On Sunday itself, tonight's dinner may not be logged yet; don't break
        // the streak for it. Any other day, an unlogged last Sunday breaks it.
        if !sundays.contains(cursor) {
            guard isSunday(now, calendar: calendar) else { return 0 }
            guard let previous = calendar.date(byAdding: .day, value: -7, to: cursor) else { return 0 }
            cursor = calendar.startOfDay(for: previous)
        }

        var count = 0
        while sundays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -7, to: cursor) else { break }
            cursor = calendar.startOfDay(for: previous)
        }
        return count
    }

    /// Calendar years between a past date and now ("2 years ago"), at least 1.
    public static func yearsAgo(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        max(1, calendar.component(.year, from: now) - calendar.component(.year, from: date))
    }

    /// "Last week", "3 weeks ago", "4 months ago", "About a year ago"…
    public static func timeAgo(days: Int) -> String {
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2..<7: return "\(days) days ago"
        case 7..<14: return "Last week"
        case 14..<45: return "\(days / 7) weeks ago"
        case 45..<320: return "\(max(2, Int((Double(days) / 30.4).rounded()))) months ago"
        case 320..<548: return "About a year ago"
        default: return "\(Int((Double(days) / 365.25).rounded())) years ago"
        }
    }

    public static let milestones: Set<Int> = [1, 10, 25, 50, 52, 100, 150, 200, 250, 300, 365, 500, 1000]

    /// A celebration line when `count` dinners is worth marking, else nil.
    public static func milestoneMessage(forDinnerCount count: Int) -> String? {
        guard milestones.contains(count) else { return nil }
        switch count {
        case 1: return "Your first Sunday dinner. Here's to many more."
        case 52: return "52 dinners: a whole year of Sundays together."
        default: return "That's \(count) Sunday dinners together."
        }
    }
}
