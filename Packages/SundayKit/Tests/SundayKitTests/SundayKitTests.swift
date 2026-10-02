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

final class WidgetStorageTests: XCTestCase {
    func testRoundTripAndCleanup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        let item = WidgetSnapshot.Item(title: "Chili", date: Date(timeIntervalSince1970: 1_800_000_000),
                                       imageFileName: "a.jpg", mealID: UUID())
        let snapshot = WidgetSnapshot(latest: item, memories: [], recentDates: [item.date], totalDinners: 12,
                                      generatedAt: Date(timeIntervalSince1970: 1_800_000_100))
        try WidgetStorage.write(snapshot, images: ["a.jpg": Data([1, 2, 3])], to: directory)
        XCTAssertEqual(WidgetStorage.read(from: directory), snapshot)
        XCTAssertEqual(WidgetStorage.imageData(named: "a.jpg", in: directory), Data([1, 2, 3]))

        try WidgetStorage.write(.empty, images: ["b.jpg": Data([4])], to: directory)
        XCTAssertNil(WidgetStorage.imageData(named: "a.jpg", in: directory), "old thumbnails are removed")
        XCTAssertEqual(WidgetStorage.read(from: directory).totalDinners, 0)

        var later = snapshot
        later.generatedAt = .now
        XCTAssertTrue(later.hasSameContent(as: snapshot))
    }

    func testCaptionsAndMemoryDependOnTheDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func d(_ y: Int, _ m: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: day, hour: 18))! }

        let sunday = d(2026, 9, 27)
        XCTAssertEqual(WidgetSnapshot.latestCaption(for: sunday, on: sunday, calendar: calendar), "Tonight")
        XCTAssertEqual(WidgetSnapshot.latestCaption(for: sunday, on: d(2026, 10, 2), calendar: calendar), "Last Sunday")
        XCTAssertNotEqual(WidgetSnapshot.latestCaption(for: sunday, on: d(2026, 10, 5), calendar: calendar), "Last Sunday")
        XCTAssertEqual(WidgetSnapshot.memoryCaption(for: d(2024, 10, 5), on: d(2026, 10, 2), calendar: calendar), "2 years ago this week")

        let chili = WidgetSnapshot.Item(title: "Chili", date: d(2025, 10, 5), imageFileName: nil, mealID: UUID())
        let snapshot = WidgetSnapshot(latest: nil, memories: [chili], recentDates: [sunday], totalDinners: 2)
        XCTAssertEqual(snapshot.memory(on: d(2026, 10, 2), calendar: calendar)?.title, "Chili")
        XCTAssertNil(snapshot.memory(on: d(2026, 11, 20), calendar: calendar))
        XCTAssertEqual(snapshot.streak(on: d(2026, 10, 2), calendar: calendar), 1)
        XCTAssertEqual(snapshot.streak(on: d(2026, 10, 9), calendar: calendar), 0)
    }

    func testReadMissingReturnsEmpty() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(WidgetStorage.read(from: directory), .empty)
    }

    func testDeepLink() {
        let id = UUID()
        XCTAssertEqual(DeepLink.mealID(from: DeepLink.url(forMeal: id)), id)
        XCTAssertNil(DeepLink.mealID(from: URL(string: "https://example.com/meal/\(id)")!))
    }
}

final class HolidaysTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 18))!
    }

    func name(_ year: Int, _ month: Int, _ day: Int) -> String? {
        Holidays.holiday(near: date(year, month, day), calendar: calendar)?.name
    }

    func testEaster() {
        let easter = Holidays.easter(2026, calendar: calendar)!
        XCTAssertEqual(calendar.dateComponents([.month, .day], from: easter), DateComponents(month: 4, day: 5))
        XCTAssertEqual(name(2026, 4, 5), "Easter")
        XCTAssertEqual(name(2025, 4, 20), "Easter")
    }

    func testSundayHolidays() {
        XCTAssertEqual(name(2026, 5, 10), "Mother's Day")
        XCTAssertEqual(name(2026, 6, 21), "Father's Day")
    }

    func testThanksgivingWeekend() {
        // Thanksgiving 2026 is Thursday Nov 26; Sunday after is Nov 29.
        XCTAssertEqual(name(2026, 11, 26), "Thanksgiving")
        XCTAssertEqual(name(2026, 11, 29), "Thanksgiving weekend")
        XCTAssertNil(name(2026, 11, 22))
    }

    func testFixedHolidaysNearby() {
        XCTAssertEqual(name(2026, 12, 27), "Christmas")
        XCTAssertEqual(name(2026, 11, 1), "Halloween")
        XCTAssertEqual(name(2027, 1, 3), "New Year's")
        XCTAssertEqual(name(2026, 12, 30), "New Year's Eve")
        XCTAssertNil(name(2026, 9, 20))
    }
}

final class UpcomingHolidayTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 18))!
    }

    func testFindsPastThanksgivingDinners() {
        let meals = [
            MealSummary(id: UUID(), name: "Turkey", date: date(2025, 11, 30), stars: 5), // Sunday after Thanksgiving 2025
            MealSummary(id: UUID(), name: "Ham", date: date(2024, 11, 28), stars: 4),    // Thanksgiving 2024
            MealSummary(id: UUID(), name: "Tacos", date: date(2025, 10, 5), stars: 3),
        ]
        let s = Suggestions(meals: meals, now: date(2026, 11, 15), calendar: calendar)
        let upcoming = s.upcomingHoliday(within: 14)
        XCTAssertEqual(upcoming?.holiday.emoji, "🦃")
        XCTAssertEqual(upcoming?.meals.map(\.name), ["Turkey", "Ham"])
    }

    func testNothingWhenNoHistory() {
        let s = Suggestions(meals: [], now: date(2026, 11, 15), calendar: calendar)
        XCTAssertNil(s.upcomingHoliday())
        let far = Suggestions(meals: [MealSummary(id: UUID(), name: "Turkey", date: date(2025, 11, 30), stars: 5)],
                              now: date(2026, 9, 1), calendar: calendar)
        XCTAssertNil(far.upcomingHoliday())
    }
}

final class ReviewRegressionTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 18) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testStreakBreaksMidweekWhenLastSundayMissing() {
        // Friday Oct 2; Sep 27 not logged, Sep 20 logged.
        XCTAssertEqual(SundayCalendar.streak(mealDates: [date(2026, 9, 20)], now: date(2026, 10, 2), calendar: calendar), 0)
    }

    func testYearsAgoUsesCalendarYears() {
        XCTAssertEqual(SundayCalendar.yearsAgo(date(2024, 10, 5), now: date(2026, 10, 2), calendar: calendar), 2)
        XCTAssertEqual(SundayCalendar.yearsAgo(date(2025, 10, 5), now: date(2026, 10, 2), calendar: calendar), 1)
    }

    func testPastYearsAcrossYearBoundary() {
        let meals = [
            MealSummary(id: UUID(), name: "Prime rib", date: date(2024, 12, 30), stars: 5),
            MealSummary(id: UUID(), name: "Leftovers", date: date(2025, 12, 30), stars: 3), // 3 days ago: too recent
        ]
        let s = Suggestions(meals: meals, now: date(2026, 1, 2), calendar: calendar)
        XCTAssertEqual(s.thisTimeInPastYears(windowDays: 7).map(\.name), ["Prime rib"])
    }

    func testUpcomingHolidaySkipsHolidaysWithoutHistory() {
        // Oct 25: Halloween (no history) comes before Thanksgiving... outside 14 days; use Nov 20 window 14
        let meals = [MealSummary(id: UUID(), name: "Turkey", date: date(2025, 11, 30), stars: 5)]
        let s = Suggestions(meals: meals, now: date(2026, 10, 28), calendar: calendar)
        XCTAssertEqual(s.upcomingHoliday(within: 30)?.holiday.emoji, "🦃", "Halloween has no history, keep looking")
    }

    func testChristmasIsNotComingAfterChristmas() {
        let meals = [MealSummary(id: UUID(), name: "Ham", date: date(2025, 12, 25), stars: 5)]
        let s = Suggestions(meals: meals, now: date(2026, 12, 27), calendar: calendar)
        XCTAssertNotEqual(s.upcomingHoliday(within: 3)?.holiday.name, "Christmas")
    }

    func testHolidayOnExactDay() {
        XCTAssertEqual(Holidays.holiday(on: date(2026, 11, 26), calendar: calendar)?.name, "Thanksgiving")
        XCTAssertNil(Holidays.holiday(on: date(2026, 11, 29), calendar: calendar))
        XCTAssertEqual(Holidays.holiday(on: date(2026, 4, 5), calendar: calendar)?.name, "Easter")
    }
}
