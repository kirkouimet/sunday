import CoreData
import SundayKit
import UIKit
import UserNotifications

/// "📸 Lemon chicken was just posted": a local notification when a dinner
/// someone else logged arrives from iCloud. CloudKit can't send custom alerts
/// for shared Core Data, but it does wake the app with silent pushes to sync,
/// so we notice new dinners on import and notify locally.
@MainActor
enum FamilyNotifier {
    static let enabledKey = "familyPostAlertsEnabled"
    private static let knownKey = "knownMealIDs"
    private static let seededKey = "knownMealIDsSeeded"
    private static let categoryID = "new-family-dinner"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static var known: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: knownKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: knownKey) }
    }

    /// Dinners you created yourself never notify.
    static func markKnown(_ id: UUID?) {
        guard let id else { return }
        known.insert(id.uuidString)
    }

    /// Call after each CloudKit import.
    static func checkForNewDinners(store: MealStore) {
        let request = NSFetchRequest<Meal>(entityName: "Meal")
        let meals = (try? store.context.fetch(request)) ?? []
        let ids = Set(meals.compactMap { $0.id?.uuidString })

        // First sync on a device: everything is "new", but none of it is news.
        guard UserDefaults.standard.bool(forKey: seededKey) else {
            known = ids
            UserDefaults.standard.set(true, forKey: seededKey)
            return
        }

        let recentCutoff = Date.now.addingTimeInterval(-3 * 86_400)
        let fresh = meals.filter { meal in
            guard let id = meal.id?.uuidString, !known.contains(id) else { return false }
            return (meal.createdAt ?? .distantPast) > recentCutoff
        }
        // Remember everything (including old dinners that just synced) so we
        // never notify twice; prune ids of deleted dinners.
        known = ids

        guard isEnabled, let newest = fresh.max(by: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) })
        else { return }
        Task { await post(newest, others: fresh.count - 1) }
    }

    private static func post(_ meal: Meal, others: Int) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
              let id = meal.id
        else { return }

        let content = UNMutableNotificationContent()
        content.title = others > 0 ? "📸 \(others + 1) new dinners posted" : "📸 New dinner posted"
        let cook = (meal.cook ?? "").isEmpty ? "" : " by \(meal.cook!)"
        content.body = others > 0
            ? "\(meal.displayName)\(cook) and more. Tap to take a look."
            : "\(meal.displayName)\(cook). How was it? Tap to rate."
        content.sound = .default
        content.threadIdentifier = categoryID
        content.userInfo = ["url": DeepLink.url(forMeal: id).absoluteString]

        if let data = meal.sortedPhotos.first?.thumbnailData,
           let url = try? writeAttachment(data, id: id),
           let attachment = try? UNNotificationAttachment(identifier: "photo", url: url) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(identifier: "dinner-\(id.uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Notification attachments must be files; the system moves them away.
    private static func writeAttachment(_ data: Data, id: UUID) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dinner-\(id.uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Opens the dinner when a notification is tapped, and shows banners while
/// the app is open.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let string = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: string)
        else { return }
        await MainActor.run { UIApplication.shared.open(url) }
    }
}
