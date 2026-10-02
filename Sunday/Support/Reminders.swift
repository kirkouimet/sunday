import CoreData
import Foundation
import SundayKit
import UserNotifications

/// The weekly "take a picture of dinner" nudge, with a memory from past years when there is one.
enum Reminders {
    static let enabledKey = "sundayReminderEnabled"
    static let hourKey = "sundayReminderHour"
    static let minuteKey = "sundayReminderMinute"
    private static let identifier = "sunday-dinner-reminder"

    static var hour: Int { UserDefaults.standard.object(forKey: hourKey) as? Int ?? 17 }
    static var minute: Int { UserDefaults.standard.object(forKey: minuteKey) as? Int ?? 30 }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    @MainActor
    static func rescheduleIfEnabled(store: MealStore) async {
        guard UserDefaults.standard.bool(forKey: enabledKey) else {
            cancel()
            return
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Sunday dinner 🍽️"
        if let memory = memoryLine(store: store) {
            content.body = "Snap a photo before everyone digs in. \(memory)"
        } else {
            content.body = "Snap a photo before everyone digs in."
        }
        content.sound = .default

        var components = DateComponents()
        components.weekday = 1 // Sunday
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    @MainActor
    private static func memoryLine(store: MealStore) -> String? {
        let meals = (try? store.context.fetch(NSFetchRequest<Meal>(entityName: "Meal"))) ?? []
        let ratings = (try? store.context.fetch(NSFetchRequest<Rating>(entityName: "Rating"))) ?? []
        let suggestions = Suggestions(meals: store.summaries(meals: meals, ratings: ratings))
        guard let past = suggestions.thisTimeInPastYears(windowDays: 7).first else { return nil }
        let years = SundayCalendar.yearsAgo(past.date)
        let when = years == 1 ? "A year ago" : "\(years) years ago"
        return "\(when) this week: \(past.name)."
    }
}
