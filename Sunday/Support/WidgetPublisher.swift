import CoreData
import SundayKit
import WidgetKit
import os

/// Writes the small snapshot the home-screen widget reads.
@MainActor
enum WidgetPublisher {
    private static let logger = Logger(subsystem: "com.kirkouimet.sunday", category: "widget")

    static func publish(store: MealStore) {
        guard !PersistenceController.isUITesting else { return }
        let mealsRequest = NSFetchRequest<Meal>(entityName: "Meal")
        mealsRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Meal.date, ascending: false)]
        let ratingsRequest = NSFetchRequest<Rating>(entityName: "Rating")
        ratingsRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Rating.updatedAt, ascending: false)]
        let meals = (try? store.context.fetch(mealsRequest)) ?? []
        let ratings = (try? store.context.fetch(ratingsRequest)) ?? []

        let suggestions = Suggestions(meals: store.summaries(meals: meals, ratings: ratings), hemisphere: .current)
        var images: [String: Data] = [:]

        func item(for meal: Meal?, caption: String) -> WidgetSnapshot.Item? {
            guard let meal, let id = meal.id, let date = meal.date else { return nil }
            var fileName: String?
            if let thumbnail = meal.sortedPhotos.first?.thumbnailData {
                fileName = "\(id.uuidString).jpg"
                images[fileName!] = thumbnail
            }
            return .init(title: meal.displayName, caption: caption, date: date, imageFileName: fileName, mealID: id)
        }

        let latestMeal = meals.first
        let latest = item(for: latestMeal, caption: latestMeal?.date.map(relativeCaption) ?? "")

        var memory: WidgetSnapshot.Item?
        if let past = suggestions.thisTimeInPastYears(windowDays: 7).first,
           let pastMeal = meals.first(where: { $0.id == past.id }) {
            let years = max(1, Calendar.current.dateComponents([.year], from: past.date, to: .now).year ?? 1)
            memory = item(for: pastMeal, caption: years == 1 ? "A year ago this week" : "\(years) years ago this week")
        }

        let snapshot = WidgetSnapshot(
            latest: latest,
            memory: memory,
            streak: SundayCalendar.streak(mealDates: meals.compactMap(\.date)),
            totalDinners: meals.count
        )
        do {
            try WidgetStorage.write(snapshot, images: images)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            logger.error("Writing widget snapshot failed: \(error.localizedDescription)")
        }
    }

    private static func relativeCaption(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Tonight" }
        if SundayCalendar.isSunday(date),
           calendar.isDate(date, inSameDayAs: SundayCalendar.mostRecentSunday(onOrBefore: .now)) {
            return "Last Sunday"
        }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
