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

final class TimeAgoTests: XCTestCase {
    func testTimeAgo() {
        XCTAssertEqual(SundayCalendar.timeAgo(days: 0), "Today")
        XCTAssertEqual(SundayCalendar.timeAgo(days: 1), "Yesterday")
        XCTAssertEqual(SundayCalendar.timeAgo(days: 5), "5 days ago")
        XCTAssertEqual(SundayCalendar.timeAgo(days: 7), "Last week")
        XCTAssertEqual(SundayCalendar.timeAgo(days: 21), "3 weeks ago")
        XCTAssertEqual(SundayCalendar.timeAgo(days: 74), "2 months ago")
        XCTAssertEqual(SundayCalendar.timeAgo(days: 214), "7 months ago")
        XCTAssertEqual(SundayCalendar.timeAgo(days: 368), "About a year ago")
        XCTAssertEqual(SundayCalendar.timeAgo(days: 800), "2 years ago")
    }
}

final class FoodTagsTests: XCTestCase {
    func testKeepsOnlyConfidentFoodLabels() {
        let tags = FoodTags.tags(from: [
            ("table", 0.9), ("child", 0.8), ("pasta", 0.7), ("salad", 0.4),
            ("pizza", 0.2), ("food", 0.95), ("pasta", 0.6),
        ])
        XCTAssertEqual(tags, ["pasta", "salad"])
    }

    func testLimitAndRoundTrip() {
        let tags = FoodTags.tags(from: [("soup", 0.9), ("bread", 0.8), ("cheese", 0.7), ("salad", 0.6)], limit: 3)
        XCTAssertEqual(tags, ["soup", "bread", "cheese"])
        XCTAssertEqual(FoodTags.decode(FoodTags.encode(tags)), tags)
        XCTAssertEqual(FoodTags.decode(nil), [])
        XCTAssertEqual(FoodTags.displayName("ice_cream"), "Ice cream")
    }
}

final class TimeAgoBoundaryTests: XCTestCase {
    func testNoOneYearsAgo() {
        for days in 320..<900 {
            XCTAssertFalse(SundayCalendar.timeAgo(days: days).hasPrefix("1 "), "\(days) days")
        }
        XCTAssertEqual(SundayCalendar.timeAgo(days: 520), "About a year ago")
        XCTAssertEqual(SundayCalendar.timeAgo(days: 548), "2 years ago")
    }
}

final class PersonalInsightTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 18))!
    }

    func testOrdinalAndComparison() {
        let first = MealSummary(id: UUID(), name: "Lemon chicken", date: date(2025, 8, 3), stars: 3)
        let second = MealSummary(id: UUID(), name: "Lemon chicken", date: date(2026, 1, 4), stars: nil)
        let third = MealSummary(id: UUID(), name: "Lemon chicken", date: date(2026, 9, 27), stars: 5)
        let dish = Suggestions.group([first, second, third]).first!
        XCTAssertEqual(PersonalInsight.line(for: third.id, in: dish, calendar: calendar),
                       "Your 3rd lemon chicken. You liked it more than in August 2025.")
        XCTAssertEqual(PersonalInsight.line(for: first.id, in: dish, calendar: calendar),
                       "Your first lemon chicken. Here's to the next one.")
        XCTAssertNil(PersonalInsight.line(for: second.id, in: dish, calendar: calendar), "unrated: nothing to say")
    }

    func testOrdinals() {
        XCTAssertEqual(PersonalInsight.ordinalString(2), "2nd")
        XCTAssertEqual(PersonalInsight.ordinalString(11), "11th")
        XCTAssertEqual(PersonalInsight.ordinalString(22), "22nd")
        XCTAssertEqual(PersonalInsight.ordinalString(103), "103rd")
    }

    func testUpcomingSunday() {
        // Friday Oct 2 2026 -> Sunday Oct 4; Sunday stays.
        XCTAssertEqual(calendar.component(.day, from: SundayCalendar.upcomingSunday(onOrAfter: date(2026, 10, 2), calendar: calendar)), 4)
        XCTAssertEqual(calendar.component(.day, from: SundayCalendar.upcomingSunday(onOrAfter: date(2026, 10, 4), calendar: calendar)), 4)
    }
}

final class AttendanceTests: XCTestCase {
    func dinner(_ day: Int, _ people: [String]) -> Attendance.Dinner {
        Attendance.Dinner(id: UUID(), date: Date(timeIntervalSince1970: Double(day) * 86_400), people: people)
    }

    func testEncodeDecode() {
        XCTAssertEqual(Attendance.encode([" Mom", "dad", "Mom", ""]), "Mom,dad")
        XCTAssertEqual(Attendance.decode("Mom, Dad,,Grandma June"), ["Mom", "Dad", "Grandma June"])
        XCTAssertEqual(Attendance.decode(nil), [])
    }

    func testFirstSundayWithNewcomer() {
        let a = dinner(0, ["Mom", "Dad"])
        let b = dinner(7, ["Mom", "Dad", "June"])
        XCTAssertNil(Attendance.moment(for: a.id, in: [a, b]), "the very first dinner has no comparison")
        XCTAssertEqual(Attendance.moment(for: b.id, in: [b, a]), "First Sunday with June")
    }

    func testMilestoneCount() {
        var dinners = (0..<9).map { dinner($0 * 7, ["Grandma"]) }
        let tenth = dinner(70, ["Grandma"])
        dinners.append(tenth)
        XCTAssertEqual(Attendance.moment(for: tenth.id, in: dinners), "Grandma's 10th Sunday")
        XCTAssertEqual(Attendance.counts(in: dinners).first?.count, 10)
    }
}

final class PlanLineTests: XCTestCase {
    func testPlanLine() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func d(_ day: Int, _ hour: Int = 18) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
        let plan = WidgetSnapshot.Item(title: "Chili", date: d(4), imageFileName: nil, mealID: UUID())
        let snapshot = WidgetSnapshot(latest: nil, memories: [], recentDates: [], totalDinners: 0, plan: plan, planCook: "Dad")
        XCTAssertEqual(snapshot.planLine(on: d(2, 9), calendar: calendar), "Sunday: Chili · Dad's cooking")
        XCTAssertEqual(snapshot.planLine(on: d(4, 9), calendar: calendar), "Tonight: Chili · Dad's cooking")
        XCTAssertNil(snapshot.planLine(on: d(5, 9), calendar: calendar))
    }
}

final class PendingRatingsTests: XCTestCase {
    func testAddReplaceAndDrain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let chili = UUID(), soup = UUID()
        try PendingRatings.add(.init(mealID: chili, stars: 3), to: directory)
        try PendingRatings.add(.init(mealID: soup, stars: 4), to: directory)
        try PendingRatings.add(.init(mealID: chili, stars: 5), to: directory)
        XCTAssertEqual(PendingRatings.stars(for: chili, in: directory), 5)
        XCTAssertEqual(PendingRatings.read(from: directory).count, 2)

        var applied: [UUID: Int] = [:]
        PendingRatings.drain(from: directory) { applied[$0.mealID] = $0.stars }
        XCTAssertEqual(applied, [chili: 5, soup: 4])
        XCTAssertTrue(PendingRatings.read(from: directory).isEmpty)
    }
}

final class LiveDinnerTests: XCTestCase {
    func testLiveWindow() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(LiveDinner.isLive(startedAt: start, endedAt: nil, now: start.addingTimeInterval(3600)))
        XCTAssertFalse(LiveDinner.isLive(startedAt: start, endedAt: nil, now: start.addingTimeInterval(6 * 3600)))
        XCTAssertFalse(LiveDinner.isLive(startedAt: start, endedAt: start.addingTimeInterval(60), now: start.addingTimeInterval(120)))
        XCTAssertFalse(LiveDinner.isLive(startedAt: nil, endedAt: nil))
    }

    func testEndsLateEvening() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: hour, minute: minute))!
        }
        XCTAssertEqual(LiveDinner.endsAt(at(17), calendar: calendar), at(22))
        XCTAssertEqual(LiveDinner.endsAt(at(20), calendar: calendar), at(23, 30))
        XCTAssertEqual(LiveDinner.endsAt(at(22, 30), calendar: calendar), at(24))
        XCTAssertFalse(LiveDinner.isLive(startedAt: at(20), endedAt: nil, now: at(23, 45), calendar: calendar))
    }

    func testStatus() {
        XCTAssertEqual(LiveDinner.status(cook: "Mom", people: 4, photos: 3), "Mom's cooking · 4 at the table · 3 photos")
        XCTAssertEqual(LiveDinner.status(cook: nil, people: 0, photos: 1), "1 photo")
    }

    func testCheckInOnce() {
        let once = LiveDinner.checkIn("Ellie", to: Attendance.encode(["Mom", "Dad"]))
        XCTAssertEqual(Attendance.decode(once), ["Mom", "Dad", "Ellie"])
        XCTAssertEqual(Attendance.decode(LiveDinner.checkIn("ellie", to: once)), ["Mom", "Dad", "Ellie"])
    }

    func testPendingCheckIns() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let chili = UUID()
        try PendingCheckIns.add(.init(mealID: chili), to: directory)
        try PendingCheckIns.add(.init(mealID: chili), to: directory)
        XCTAssertTrue(PendingCheckIns.contains(chili, in: directory))
        var drained: [UUID] = []
        PendingCheckIns.drain(from: directory) { drained.append($0.mealID); return true }
        XCTAssertEqual(drained, [chili])
        XCTAssertTrue(PendingCheckIns.read(from: directory).isEmpty)
    }

    func testPendingCheckInsWaitForSyncButExpire() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fresh = UUID(), old = UUID()
        try PendingCheckIns.add(.init(mealID: fresh), to: directory)
        try PendingCheckIns.add(.init(mealID: old, at: .now.addingTimeInterval(-7 * 3600)), to: directory)
        var seen: [UUID] = []
        PendingCheckIns.drain(from: directory) { seen.append($0.mealID); return false }
        XCTAssertEqual(seen, [fresh]) // The week-old tap is never applied.
        XCTAssertEqual(PendingCheckIns.read(from: directory).map(\.mealID), [fresh])
    }
}

final class WidgetStorageCleanupTests: XCTestCase {
    func testWritingSnapshotKeepsQueues() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let meal = UUID()
        try PendingRatings.add(.init(mealID: meal, stars: 4), to: directory)
        try PendingCheckIns.add(.init(mealID: meal), to: directory)
        try Data([1]).write(to: directory.appendingPathComponent("old.jpg"))
        try Data([1]).write(to: directory.appendingPathComponent("live-x.jpg"))
        let snapshot = WidgetSnapshot(latest: nil, memories: [], recentDates: [], totalDinners: 0)
        try WidgetStorage.write(snapshot, images: ["new.jpg": Data([2])], to: directory)
        XCTAssertEqual(PendingRatings.stars(for: meal, in: directory), 4)
        XCTAssertTrue(PendingCheckIns.contains(meal, in: directory))
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        XCTAssertFalse(files.contains("old.jpg"))
        XCTAssertTrue(files.contains("new.jpg"))
        XCTAssertTrue(files.contains("live-x.jpg"))
    }
}

final class StructuredRecipeTests: XCTestCase {
    func testFormattedAndRoundTrip() {
        let recipe = StructuredRecipe(ingredients: ["2 lemons", " ", "1 chicken"], steps: ["Roast it.", "Squeeze."], note: "Grandma's way")
        XCTAssertEqual(recipe.ingredients, ["2 lemons", "1 chicken"])
        XCTAssertEqual(recipe.formatted, "Ingredients\n• 2 lemons\n• 1 chicken\n\nSteps\n1. Roast it.\n2. Squeeze.\n\n“Grandma's way”")
        XCTAssertEqual(StructuredRecipe.decode(recipe.encoded), recipe)
        XCTAssertNil(StructuredRecipe.decode("nope"))
    }
}

final class RecipeChunkingTests: XCTestCase {
    func testChunksAtSentences() {
        let sentence = "Brown the onions slowly. "
        let text = String(repeating: sentence, count: 400) // ~10k characters
        let chunks = StructuredRecipe.chunks(of: text, max: 5_000)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 5_000 })
        XCTAssertEqual(chunks.joined(), text)
    }

    func testMergeDeduplicatesIngredients() {
        let merged = StructuredRecipe.merged([
            .init(ingredients: ["2 onions", "Salt"], steps: ["Chop."]),
            .init(ingredients: ["salt", "Beef"], steps: ["Brown."], note: "Low and slow"),
        ])
        XCTAssertEqual(merged.ingredients, ["2 onions", "Salt", "Beef"])
        XCTAssertEqual(merged.steps, ["Chop.", "Brown."])
        XCTAssertEqual(merged.note, "Low and slow")
    }

    func testParseRoundTripAfterTypoFix() {
        let recipe = StructuredRecipe(ingredients: ["2 lemons", "1 chicken"], steps: ["Roast it.", "Squeeze."], note: "Grandma's way")
        let edited = recipe.formatted.replacingOccurrences(of: "Roast it.", with: "Roast it at 425°F.")
        let parsed = StructuredRecipe.parse(edited)
        XCTAssertEqual(parsed?.ingredients, ["2 lemons", "1 chicken"])
        XCTAssertEqual(parsed?.steps, ["Roast it at 425°F.", "Squeeze."])
        XCTAssertEqual(parsed?.note, "Grandma's way")
        XCTAssertNil(StructuredRecipe.parse("Just brown it and add beans."))
    }

    func testAvatarPaletteIsStable() {
        XCTAssertEqual(AvatarPalette.index(for: "Ellie"), AvatarPalette.index(for: " ellie "))
        XCTAssertEqual(AvatarPalette.initial(for: "grandma June"), "G")
    }
}

final class AppSettingsTests: XCTestCase {
    func testOlderBuildsMustUpdate() {
        let settings = AppSettings(minimumVersion: "1.2")
        XCTAssertTrue(settings.requiresUpdate(from: "1.1"))
        XCTAssertTrue(settings.requiresUpdate(from: "1.1.9"))
        XCTAssertTrue(settings.requiresUpdate(from: "0.9"))
        XCTAssertFalse(settings.requiresUpdate(from: "1.2"))
        XCTAssertFalse(settings.requiresUpdate(from: "1.2.0"))
        XCTAssertFalse(settings.requiresUpdate(from: "1.10"))
        XCTAssertFalse(settings.requiresUpdate(from: "2.0"))
    }

    func testComparesNumbersNotText() {
        XCTAssertTrue(AppSettings(minimumVersion: "1.10").requiresUpdate(from: "1.9"))
        XCTAssertTrue(AppSettings(minimumVersion: "1.2.1").requiresUpdate(from: "1.2"))
    }

    func testABrokenFileNeverLocksAnyoneOut() {
        XCTAssertFalse(AppSettings().requiresUpdate(from: "1.0"))
        XCTAssertFalse(AppSettings(minimumVersion: "").requiresUpdate(from: "1.0"))
        XCTAssertFalse(AppSettings(minimumVersion: "soon").requiresUpdate(from: "1.0"))
        XCTAssertFalse(AppSettings(minimumVersion: "2.0").requiresUpdate(from: "dev"))
    }

    func testDecodesWithFieldsMissing() throws {
        let json = Data(#"{"minimumVersion":"1.3","updateURL":"https://sunday.cooking/update"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(settings.minimumVersion, "1.3")
        XCTAssertNil(settings.message)
        XCTAssertEqual(settings.updateURL?.host, "sunday.cooking")
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)), AppSettings())
    }
}

final class MealDescriptionTests: XCTestCase {
    func testTidiesTheModelsHabits() {
        let description = MealDescription.cleaned(name: " \"Spaghetti with Meat Sauce.\" ",
                                                  caption: "Spaghetti with meat sauce and cheese", isFood: true)
        XCTAssertEqual(description, MealDescription(name: "Spaghetti with meat sauce",
                                                    caption: "Spaghetti with meat sauce and cheese."))
    }

    func testKeepsCapitalsThatAreMeant() {
        XCTAssertEqual(MealDescription.sentenceCased("BBQ Ribs and Corn"), "BBQ ribs and corn")
        XCTAssertEqual(MealDescription.sentenceCased("lasagna"), "Lasagna")
    }

    func testNotFoodIsNothing() {
        XCTAssertNil(MealDescription.cleaned(name: "", caption: "A dog is standing in a grassy area.", isFood: true))
        XCTAssertNil(MealDescription.cleaned(name: "Dog", caption: "A dog on grass.", isFood: false))
        XCTAssertNil(MealDescription.cleaned(name: String(repeating: "very ", count: 20), caption: "", isFood: true))
    }

    func testARamblingCaptionIsDroppedButTheNameKept() {
        let description = MealDescription.cleaned(name: "Tacos", caption: String(repeating: "word ", count: 60), isFood: true)
        XCTAssertEqual(description, MealDescription(name: "Tacos", caption: ""))
    }
}
