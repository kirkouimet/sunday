import Foundation

/// Holidays a family dinner tends to cluster around. Sunday dinners rarely
/// land on the holiday itself, so most match within a few days.
public struct Holiday: Hashable, Sendable {
    public let name: String
    public let emoji: String

    public var label: String { "\(emoji) \(name)" }
}

public enum Holidays {
    /// The holiday a dinner on `date` belongs to, if any (US calendar).
    public static func holiday(near date: Date, calendar: Calendar = .current) -> Holiday? {
        let year = calendar.component(.year, from: date)
        let day = calendar.startOfDay(for: date)

        func distance(to other: Date?) -> Int? {
            guard let other else { return nil }
            return calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: other)).day
        }
        func on(_ month: Int, _ dayOfMonth: Int, year y: Int = year) -> Date? {
            calendar.date(from: DateComponents(year: y, month: month, day: dayOfMonth))
        }

        // Sunday holidays: exact match.
        if distance(to: easter(year, calendar: calendar)) == 0 { return Holiday(name: "Easter", emoji: "🐣") }
        if distance(to: nthWeekday(2, weekday: 1, month: 5, year: year, calendar: calendar)) == 0 {
            return Holiday(name: "Mother's Day", emoji: "💐")
        }
        if distance(to: nthWeekday(3, weekday: 1, month: 6, year: year, calendar: calendar)) == 0 {
            return Holiday(name: "Father's Day", emoji: "👔")
        }

        // Thanksgiving (4th Thursday of November) and its weekend.
        if let gap = distance(to: nthWeekday(4, weekday: 5, month: 11, year: year, calendar: calendar)) {
            if gap == 0 { return Holiday(name: "Thanksgiving", emoji: "🦃") }
            if (-3 ... -1).contains(gap) { return Holiday(name: "Thanksgiving weekend", emoji: "🦃") }
        }

        // Fixed-date holidays: within three days either side.
        let fixed: [(Int, Int, Holiday)] = [
            (12, 25, Holiday(name: "Christmas", emoji: "🎄")),
            (12, 31, Holiday(name: "New Year's Eve", emoji: "🎆")),
            (1, 1, Holiday(name: "New Year's", emoji: "🎆")),
            (7, 4, Holiday(name: "Fourth of July", emoji: "🎇")),
            (10, 31, Holiday(name: "Halloween", emoji: "🎃")),
            (2, 14, Holiday(name: "Valentine's Day", emoji: "❤️")),
        ]
        var best: (gap: Int, holiday: Holiday)?
        for (month, dayOfMonth, holiday) in fixed {
            // Check neighbouring years too, so Dec 29 can match New Year's Day.
            for y in [year - 1, year, year + 1] {
                guard let gap = distance(to: on(month, dayOfMonth, year: y)), abs(gap) <= 3 else { continue }
                if best == nil || abs(gap) < abs(best!.gap) { best = (gap, holiday) }
            }
        }
        return best?.holiday
    }

    /// The holiday that falls exactly on `date`, if any.
    public static func holiday(on date: Date, calendar: Calendar = .current) -> Holiday? {
        let year = calendar.component(.year, from: date)
        let parts = calendar.dateComponents([.month, .day], from: date)
        func same(_ other: Date?) -> Bool { other.map { calendar.isDate($0, inSameDayAs: date) } ?? false }

        if same(easter(year, calendar: calendar)) { return Holiday(name: "Easter", emoji: "🐣") }
        if same(nthWeekday(2, weekday: 1, month: 5, year: year, calendar: calendar)) { return Holiday(name: "Mother's Day", emoji: "💐") }
        if same(nthWeekday(3, weekday: 1, month: 6, year: year, calendar: calendar)) { return Holiday(name: "Father's Day", emoji: "👔") }
        if same(nthWeekday(4, weekday: 5, month: 11, year: year, calendar: calendar)) { return Holiday(name: "Thanksgiving", emoji: "🦃") }
        switch (parts.month, parts.day) {
        case (12, 25): return Holiday(name: "Christmas", emoji: "🎄")
        case (12, 31): return Holiday(name: "New Year's Eve", emoji: "🎆")
        case (1, 1): return Holiday(name: "New Year's", emoji: "🎆")
        case (7, 4): return Holiday(name: "Fourth of July", emoji: "🎇")
        case (10, 31): return Holiday(name: "Halloween", emoji: "🎃")
        case (2, 14): return Holiday(name: "Valentine's Day", emoji: "❤️")
        default: return nil
        }
    }

    /// Western (Gregorian) Easter Sunday, anonymous Gregorian algorithm.
    public static func easter(_ year: Int, calendar: Calendar = .current) -> Date? {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// The nth `weekday` (1 = Sunday) of a month.
    static func nthWeekday(_ n: Int, weekday: Int, month: Int, year: Int, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, weekday: weekday, weekdayOrdinal: n))
    }
}
