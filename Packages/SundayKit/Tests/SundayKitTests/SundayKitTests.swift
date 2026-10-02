import XCTest
@testable import SundayKit

final class SeasonTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testNorthernSeasons() {
        XCTAssertEqual(Season.of(date(2026, 1, 15), calendar: calendar), .winter)
        XCTAssertEqual(Season.of(date(2026, 3, 1), calendar: calendar), .spring)
        XCTAssertEqual(Season.of(date(2026, 7, 4), calendar: calendar), .summer)
        XCTAssertEqual(Season.of(date(2026, 10, 31), calendar: calendar), .fall)
        XCTAssertEqual(Season.of(date(2026, 12, 25), calendar: calendar), .winter)
    }

    func testSouthernSeasonsAreFlipped() {
        XCTAssertEqual(Season.of(date(2026, 12, 25), calendar: calendar, hemisphere: .southern), .summer)
        XCTAssertEqual(Season.of(date(2026, 4, 10), calendar: calendar, hemisphere: .southern), .fall)
    }
}

final class SuggestionsTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func meal(_ name: String, _ date: Date, _ stars: Int? = nil) -> MealSummary {
        MealSummary(id: UUID(), name: name, date: date, stars: stars)
    }

    func testNormalizeGroupsSameDish() {
        XCTAssertEqual(MealName.normalize("  Lemon   Chicken "), "lemon chicken")
        XCTAssertEqual(MealName.normalize("Crème Brûlée"), "creme brulee")

        let dishes = Suggestions.group([
            meal("Lemon Chicken", date(2026, 1, 4), 5),
            meal("lemon chicken", date(2026, 3, 1), 3),
            meal("Tacos", date(2026, 2, 1)),
        ])
        XCTAssertEqual(dishes.count, 2)
        let lemon = dishes.first { $0.key == "lemon chicken" }!
        XCTAssertEqual(lemon.timesEaten, 2)
        XCTAssertEqual(lemon.averageStars, 4)
        XCTAssertEqual(lemon.lastEaten, date(2026, 3, 1))
        XCTAssertEqual(lemon.displayName, "lemon chicken")
    }

    func testBlankNamesAreIgnored() {
        XCTAssertTrue(Suggestions.group([meal("   ", date(2026, 1, 1))]).isEmpty)
    }

    func testFavoritesDue() {
        let s = Suggestions(meals: [
            meal("Lasagna", date(2026, 5, 3), 5),          // great, long ago
            meal("Pot roast", date(2026, 7, 5), 4),        // good, long ago
            meal("Fish sticks", date(2026, 6, 1), 2),      // bad
            meal("Pizza", date(2026, 9, 27), 5),           // great, too recent
            meal("Mystery stew", date(2026, 1, 1)),        // unrated
        ], now: date(2026, 10, 2), calendar: calendar)

        XCTAssertEqual(s.favoritesDue().map(\.key), ["lasagna", "pot roast"])
    }

    func testThisTimeInPastYears() {
        let s = Suggestions(meals: [
            meal("Chili", date(2025, 10, 5)),
            meal("Soup", date(2024, 9, 20)),
            meal("BBQ", date(2025, 7, 4)),
            meal("Squash", date(2026, 9, 28)), // this year, excluded
        ], now: date(2026, 10, 2), calendar: calendar)

        XCTAssertEqual(s.thisTimeInPastYears().map(\.name), ["Chili", "Soup"])
    }

    func testThisTimeInPastYearsHandlesLeapDay() {
        let s = Suggestions(meals: [meal("Leap pie", date(2025, 3, 1))],
                            now: date(2028, 2, 29), calendar: calendar)
        XCTAssertEqual(s.thisTimeInPastYears(windowDays: 1).map(\.name), ["Leap pie"])
    }

    func testGoodForThisSeason() {
        let s = Suggestions(meals: [
            meal("Chili", date(2025, 10, 5), 5),
            meal("Chili", date(2024, 11, 3), 4),
            meal("Soup", date(2025, 9, 20)),
            meal("BBQ", date(2025, 7, 4), 5),
            meal("Gross casserole", date(2025, 10, 12), 1),
        ], now: date(2026, 10, 2), calendar: calendar)

        XCTAssertEqual(s.goodForThisSeason().map(\.key), ["chili", "soup"])
    }

    func testNameSuggestions() {
        let s = Suggestions(meals: [
            meal("Chicken tikka", date(2026, 1, 1)),
            meal("Lemon chicken", date(2026, 2, 1)),
            meal("Chili", date(2026, 3, 1)),
        ], now: date(2026, 10, 2), calendar: calendar)

        XCTAssertEqual(s.nameSuggestions(for: "chi"), ["Chili", "Chicken tikka", "Lemon chicken"])
        XCTAssertEqual(s.nameSuggestions(for: "chili"), [])
        XCTAssertEqual(s.nameSuggestions(for: " "), [])
    }

    func testSurpriseFallsBackWhenNoFavorites() {
        let s = Suggestions(meals: [meal("Tacos", date(2026, 9, 30))],
                            now: date(2026, 10, 2), calendar: calendar)
        XCTAssertEqual(s.surprise()?.key, "tacos")
        XCTAssertNil(Suggestions(meals: [], now: .now).surprise())
    }
}

final class SundayCalendarTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 18) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // 2026-09-27 and 2026-10-04 are Sundays; 2026-10-02 is a Friday.

    func testMostRecentSunday() {
        let sunday = SundayCalendar.mostRecentSunday(onOrBefore: date(2026, 10, 2), calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: sunday), DateComponents(year: 2026, month: 9, day: 27))
        XCTAssertEqual(SundayCalendar.mostRecentSunday(onOrBefore: date(2026, 10, 4), calendar: calendar), date(2026, 10, 4))
        XCTAssertTrue(SundayCalendar.isSunday(date(2026, 10, 4), calendar: calendar))
        XCTAssertFalse(SundayCalendar.isSunday(date(2026, 10, 2), calendar: calendar))
    }

    func testStreakCountsConsecutiveSundays() {
        let dates = [date(2026, 9, 27), date(2026, 9, 20), date(2026, 9, 13), date(2026, 8, 30), date(2026, 9, 16)]
        XCTAssertEqual(SundayCalendar.streak(mealDates: dates, now: date(2026, 10, 2), calendar: calendar), 3)
    }

    func testStreakSurvivesUnloggedToday() {
        let dates = [date(2026, 9, 27), date(2026, 9, 20)]
        XCTAssertEqual(SundayCalendar.streak(mealDates: dates, now: date(2026, 10, 4, hour: 9), calendar: calendar), 2)
        XCTAssertEqual(SundayCalendar.streak(mealDates: dates + [date(2026, 10, 4)], now: date(2026, 10, 4), calendar: calendar), 3)
    }

    func testStreakBrokenByMissedSunday() {
        XCTAssertEqual(SundayCalendar.streak(mealDates: [date(2026, 9, 13)], now: date(2026, 10, 2), calendar: calendar), 0)
        XCTAssertEqual(SundayCalendar.streak(mealDates: [], now: date(2026, 10, 2), calendar: calendar), 0)
    }

    func testMilestones() {
        XCTAssertNotNil(SundayCalendar.milestoneMessage(forDinnerCount: 1))
        XCTAssertEqual(SundayCalendar.milestoneMessage(forDinnerCount: 100), "That's 100 Sunday dinners together.")
        XCTAssertNil(SundayCalendar.milestoneMessage(forDinnerCount: 7))
    }
}
