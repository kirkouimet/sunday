import CoreData
import SundayKit
import WidgetKit
import os

/// Writes the small snapshot the home-screen widget reads.
@MainActor
enum WidgetPublisher {
    private static let logger = Logger(subsystem: "com.kirkouimet.sunday", category: "widget")
    private static var lastPublished: WidgetSnapshot?

    static func publish(store: MealStore) {
        guard !PersistenceController.isUITesting else { return }
        let mealsRequest = NSFetchRequest<Meal>(entityName: "Meal")
        mealsRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Meal.date, ascending: false)]
        let all = (try? store.context.fetch(mealsRequest)) ?? []
        let meals = all.filter { !$0.isPlan }
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let upcomingPlan = all.filter { $0.isPlan && ($0.date ?? .distantPast) >= startOfToday }
            .min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }

        var images: [String: Data] = [:]
        func item(for meal: Meal) -> WidgetSnapshot.Item? {
            guard let id = meal.id, let date = meal.date else { return nil }
            var fileName: String?
            // Named by photo, so a changed cover photo gets a new file.
            if let photo = meal.sortedPhotos.first, let photoID = photo.id, let thumbnail = photo.thumbnailData {
                fileName = "\(photoID.uuidString).jpg"
                images[fileName!] = thumbnail
            }
            return .init(title: meal.displayName, date: date, imageFileName: fileName, mealID: id)
        }

        // Past-year dinners that could be "this week in years past" at any
        // point in the next week (the widget picks per day).
        let summaries = meals.compactMap { m -> MealSummary? in
            guard let id = m.id, let date = m.date else { return nil }
            return MealSummary(id: id, name: m.displayName, date: date, stars: nil)
        }
        let nextWeek = Calendar.current.date(byAdding: .day, value: 4, to: .now) ?? .now
        let candidateIDs = Set(Suggestions(meals: summaries, now: nextWeek).thisTimeInPastYears(windowDays: 11).prefix(8).map(\.id))
        let memories = meals.filter { $0.id.map(candidateIDs.contains) ?? false }.compactMap(item(for:))

        let snapshot = WidgetSnapshot(
            latest: meals.first.flatMap(item(for:)),
            memories: memories,
            recentDates: Array(meals.compactMap(\.date).prefix(120)),
            totalDinners: meals.count,
            plan: upcomingPlan.flatMap(item(for:)),
            planCook: upcomingPlan?.cook.flatMap { $0.isEmpty ? nil : $0 }
        )

        if let lastPublished, lastPublished.hasSameContent(as: snapshot) { return }
        do {
            try WidgetStorage.write(snapshot, images: images)
            lastPublished = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            logger.error("Writing widget snapshot failed: \(error.localizedDescription)")
        }
    }
}
