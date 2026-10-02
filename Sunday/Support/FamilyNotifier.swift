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
        // A planned dinner (no photo yet) isn't news; leave it "unknown" so
        // it announces itself once someone snaps it.
        let meals = ((try? store.context.fetch(request)) ?? []).filter { !$0.sortedPhotos.isEmpty }
        let ids = Set(meals.compactMap { $0.id?.uuidString })

        // Until this device's first full sync (both stores) is done, every
        // dinner looks new but none of it is news: just remember them all.
        // Also nothing to announce when there's no family.
        guard UserDefaults.standard.bool(forKey: seededKey) || store.hasCompletedFirstImport else {
            known = ids
            return
        }
        if !UserDefaults.standard.bool(forKey: seededKey) {
            known = ids
            UserDefaults.standard.set(true, forKey: seededKey)
            return
        }
        guard store.role != .solo else {
            known = ids
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

    // MARK: Sunday Live

    private static let knownLiveKey = "knownLiveMealIDs"

    /// "I'm here" and "Snap a photo", right on the notification.
    static func registerCategories() {
        let checkIn = UNNotificationAction(identifier: LiveNotification.checkInAction, title: "I'm here", options: [])
        let snap = UNNotificationAction(identifier: LiveNotification.snapAction, title: "Snap a photo", options: [.foreground],
                                        icon: UNNotificationActionIcon(systemImageName: "camera.fill"))
        let live = UNNotificationCategory(identifier: LiveNotification.categoryID, actions: [checkIn, snap], intentIdentifiers: [])
        // A phone that doesn't know whose it is opens the app to ask.
        let askFirst = UNNotificationAction(identifier: LiveNotification.checkInAction, title: "I'm here", options: [.foreground])
        let liveAsk = UNNotificationCategory(identifier: LiveNotification.askCategoryID, actions: [askFirst, snap], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([live, liveAsk])
    }

    private static var knownLive: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: knownLiveKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(50)), forKey: knownLiveKey) }
    }

    static func markLiveKnown(_ id: UUID?) {
        guard let id else { return }
        knownLive.insert(id.uuidString)
    }

    /// Someone else just sat down to dinner: "Mom's cooking Chili. At the
    /// table?" CloudKit can't push a Live Activity to the family without a
    /// server, so the import's silent push becomes a local alert instead,
    /// and the Live Activity starts when you open the app.
    static func checkForLiveDinner(store: MealStore) {
        guard isEnabled, store.role != .solo, let meal = store.liveMeal(), let id = meal.id,
              !knownLive.contains(id.uuidString)
        else { return }
        knownLive.insert(id.uuidString)
        // Only fresh news: a dinner that started a while ago isn't an invite.
        guard Date.now.timeIntervalSince(meal.liveAt ?? .distantPast) < 2 * 3600, !store.isCheckedIn(meal) else { return }
        Task { await postLive(meal, id: id, store: store) }
    }

    private static func postLive(_ meal: Meal, id: UUID, store: MealStore) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "🍽️ Sunday dinner is on"
        // Never invent a cook: whoever tapped "sitting down" just sat down.
        let dish = (meal.name ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? nil : meal.displayName
        if let cook = meal.cook, !cook.isEmpty {
            content.body = "\(cook)'s cooking \(dish ?? "dinner"). At the table?"
        } else if let starter = meal.liveBy {
            content.body = "\(starter) sat down to \(dish ?? "dinner"). At the table?"
        } else {
            content.body = "\(dish ?? "Dinner")'s on. At the table?"
        }
        content.sound = .default
        content.categoryIdentifier = store.myName == nil ? LiveNotification.askCategoryID : LiveNotification.categoryID
        content.threadIdentifier = LiveNotification.categoryID
        content.userInfo = ["mealID": id.uuidString]
        let request = UNNotificationRequest(identifier: "live-\(id.uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Notification attachments must be files; the system moves them away.
    private static func writeAttachment(_ data: Data, id: UUID) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dinner-\(id.uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// Identifiers for the "dinner is on" notification and its buttons.
enum LiveNotification {
    static let categoryID = "live-dinner"
    static let askCategoryID = "live-dinner-ask"
    static let checkInAction = "check-in"
    static let snapAction = "snap"
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
        let info = response.notification.request.content.userInfo
        if let mealID = (info["mealID"] as? String).flatMap(UUID.init(uuidString:)) {
            switch response.actionIdentifier {
            case LiveNotification.checkInAction:
                try? PendingCheckIns.add(.init(mealID: mealID))
                // Give iCloud time to send the check-in before iOS suspends us.
                let task = await MainActor.run { UIApplication.shared.beginBackgroundTask(withName: "check-in") }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(25))
                    UIApplication.shared.endBackgroundTask(task)
                }
                await MainActor.run {
                    CheckInIntent.onCheckIn?()
                    if MealStore.shared.needsMyName { UIApplication.shared.open(DeepLink.live) }
                }
            case LiveNotification.snapAction:
                await MainActor.run { UIApplication.shared.open(DeepLink.snap) }
            default:
                break // Opens the app to the live dinner on the feed.
            }
            return
        }
        guard let string = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: string)
        else { return }
        await MainActor.run { UIApplication.shared.open(url) }
    }
}
