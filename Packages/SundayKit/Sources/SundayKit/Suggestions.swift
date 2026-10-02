import Foundation

/// A plain snapshot of one logged dinner, decoupled from Core Data so the
/// suggestion logic can be tested anywhere.
public struct MealSummary: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let date: Date
    /// The current user's private rating, 1...5, or nil if unrated.
    public let stars: Int?

    public init(id: UUID, name: String, date: Date, stars: Int?) {
        self.id = id
        self.name = name
        self.date = date
        self.stars = stars
    }
}

/// Every time the family ate "the same thing", grouped by normalized name.
public struct Dish: Hashable, Sendable, Identifiable {
    public let key: String
    /// Newest first.
    public let meals: [MealSummary]

    public var id: String { key }
    public var displayName: String { meals[0].name }
    public var lastEaten: Date { meals[0].date }
    public var latestMealID: UUID { meals[0].id }
    public var timesEaten: Int { meals.count }

    public var averageStars: Double? {
        let rated = meals.compactMap(\.stars)
        guard !rated.isEmpty else { return nil }
        return Double(rated.reduce(0, +)) / Double(rated.count)
    }

    public func daysSinceLastEaten(now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: lastEaten, to: now).day ?? 0
    }
}

public enum MealName {
    /// "  Lemon   Chicken " and "lemon chicken" are the same dish.
    public static func normalize(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

public struct Suggestions: Sendable {
    public let dishes: [Dish]
    public let now: Date
    public let calendar: Calendar
    public let hemisphere: Hemisphere

    public init(
        meals: [MealSummary],
        now: Date = .now,
        calendar: Calendar = .current,
        hemisphere: Hemisphere = .northern
    ) {
        self.now = now
        self.calendar = calendar
        self.hemisphere = hemisphere
        self.dishes = Suggestions.group(meals)
    }

    public static func group(_ meals: [MealSummary]) -> [Dish] {
        let named = meals.filter { !MealName.normalize($0.name).isEmpty }
        return Dictionary(grouping: named) { MealName.normalize($0.name) }
            .map { key, meals in Dish(key: key, meals: meals.sorted { $0.date > $1.date }) }
            .sorted { $0.lastEaten > $1.lastEaten }
    }

    /// Highly rated dishes you haven't had in a while, best and longest-missed first.
    public func favoritesDue(minStars: Double = 4, minDaysSince: Int = 42) -> [Dish] {
        dishes
            .filter { ($0.averageStars ?? 0) >= minStars && $0.daysSinceLastEaten(now: now, calendar: calendar) >= minDaysSince }
            .sorted {
                let a = $0.averageStars ?? 0, b = $1.averageStars ?? 0
                if a != b { return a > b }
                return $0.lastEaten < $1.lastEaten
            }
    }

    /// Meals from earlier years that fell within `windowDays` of today's date
    /// (across year boundaries: on Jan 2, a Dec 30 dinner counts).
    public func thisTimeInPastYears(windowDays: Int = 21) -> [MealSummary] {
        let today = calendar.dateComponents([.month, .day], from: now)
        let recentCutoff = calendar.date(byAdding: .day, value: -300, to: now) ?? now
        return dishes.flatMap(\.meals)
            .filter { meal in
                guard meal.date < recentCutoff else { return false }
                let year = calendar.component(.year, from: meal.date)
                let closest = [year - 1, year, year + 1].compactMap { y -> Int? in
                    guard let anniversary = calendar.date(from: DateComponents(year: y, month: today.month, day: today.day))
                    else { return nil }
                    return abs(calendar.dateComponents([.day], from: anniversary, to: meal.date).day ?? .max)
                }.min() ?? .max
                return closest <= windowDays
            }
            .sorted { $0.date > $1.date }
    }

    /// Dishes the family tends to eat in the current season, skipping anything
    /// rated poorly or eaten very recently.
    public func goodForThisSeason(minDaysSince: Int = 14) -> [Dish] {
        let season = Season.of(now, calendar: calendar, hemisphere: hemisphere)
        return dishes
            .compactMap { dish -> (Dish, Int)? in
                let count = dish.meals.filter { Season.of($0.date, calendar: calendar, hemisphere: hemisphere) == season }.count
                guard count > 0,
                      (dish.averageStars ?? 3) >= 3,
                      dish.daysSinceLastEaten(now: now, calendar: calendar) >= minDaysSince
                else { return nil }
                return (dish, count)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return ($0.0.averageStars ?? 0) > ($1.0.averageStars ?? 0)
            }
            .map(\.0)
    }

    /// The next holiday within `days` that the family has history for, and the
    /// dinners from that holiday in earlier years (newest first).
    public func upcomingHoliday(within days: Int = 14) -> (holiday: Holiday, meals: [MealSummary])? {
        let today = calendar.startOfDay(for: now)
        let recentCutoff = calendar.date(byAdding: .day, value: -300, to: now) ?? now
        let pastMeals = dishes.flatMap(\.meals).filter { $0.date < recentCutoff }
        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let holiday = Holidays.holiday(on: day, calendar: calendar)
            else { continue }
            let past = pastMeals.filter { Holidays.holiday(near: $0.date, calendar: calendar)?.emoji == holiday.emoji }
            guard !past.isEmpty else { continue }
            return (holiday, past.sorted { $0.date > $1.date })
        }
        return nil
    }

    /// A random pick for "Surprise me": prefers favorites, falls back to anything decent.
    public func surprise<G: RandomNumberGenerator>(using generator: inout G) -> Dish? {
        let pool = favoritesDue(minDaysSince: 14)
        if let pick = pool.randomElement(using: &generator) { return pick }
        return dishes.filter { ($0.averageStars ?? 3) >= 3 }.randomElement(using: &generator)
    }

    public func surprise() -> Dish? {
        var generator = SystemRandomNumberGenerator()
        return surprise(using: &generator)
    }

    /// All earlier dinners of the same dish as `name`.
    public func dish(named name: String) -> Dish? {
        let key = MealName.normalize(name)
        return dishes.first { $0.key == key }
    }

    /// Previously used dish names that start with or contain `prefix`, most recent first.
    public func nameSuggestions(for prefix: String, limit: Int = 5) -> [String] {
        let query = MealName.normalize(prefix)
        guard !query.isEmpty else { return [] }
        let matches = dishes.filter { $0.key.contains(query) && $0.key != query }
        let starts = matches.filter { $0.key.hasPrefix(query) }
        let rest = matches.filter { !$0.key.hasPrefix(query) }
        return (starts + rest).prefix(limit).map(\.displayName)
    }
}
