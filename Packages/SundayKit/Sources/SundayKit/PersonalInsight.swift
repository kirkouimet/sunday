import Foundation

/// "The table remembers": a private line for the person looking at a dinner,
/// built only from their own stars. Never compares with anyone else.
public enum PersonalInsight {
    public static func line(for mealID: UUID, in dish: Dish, calendar: Calendar = .current) -> String? {
        let chronological = dish.meals.sorted { $0.date < $1.date }
        guard let index = chronological.firstIndex(where: { $0.id == mealID }),
              let stars = chronological[index].stars
        else { return nil }

        let name = dish.displayName.lowercased()
        let ordinal = index + 1
        guard ordinal > 1 else { return "Your first \(name). Here's to the next one." }

        let lead = "Your \(ordinalString(ordinal)) \(name)."
        // The most recent earlier time you rated it.
        guard let previous = chronological[..<index].last(where: { $0.stars != nil }),
              let previousStars = previous.stars
        else { return lead }

        let when = previous.date.formatted(.dateTime.month(.wide).year())
        if stars > previousStars { return "\(lead) You liked it more than in \(when)." }
        if stars < previousStars { return "\(lead) Not quite as good as \(when)." }
        return "\(lead) Just as good as \(when)."
    }

    static func ordinalString(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}

extension SundayCalendar {
    /// Today if it's Sunday, otherwise the coming Sunday (same time of day).
    public static func upcomingSunday(onOrAfter date: Date, calendar: Calendar = .current) -> Date {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        let days = (8 - weekday) % 7
        return calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
}
