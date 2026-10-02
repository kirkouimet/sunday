import ActivityKit
import SundayKit
import UIKit
import os

/// Keeps this phone's Live Activity in step with the dinner happening now:
/// starts it (only possible while the app is open), updates the faces and
/// photo count as check-ins and photos sync in, and ends it when the
/// evening is wrapped up or the window passes.
@MainActor
enum LiveDinners {
    private static let logger = Logger(subsystem: "com.kirkouimet.sunday", category: "live")

    /// The newest photo, small, where the widget extension can read it.
    private static func writeThumbnail(of meal: Meal, id: String) -> String? {
        guard let newest = meal.sortedPhotos.max(by: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }),
              let data = newest.thumbnailData, let photoID = newest.id,
              let directory = WidgetStorage.directory
        else { return nil }
        let name = "live-\(id)-\(photoID.uuidString).jpg"
        removeLiveThumbnails(except: name)
        let url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        return name
    }

    private static func removeLiveThumbnails(except keep: String? = nil) {
        guard let directory = WidgetStorage.directory else { return }
        for file in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        where file.hasPrefix("live-") && file != keep {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    static func sync(store: MealStore) {
        guard !PersistenceController.isUITesting else { return }
        let live = store.liveMeal()
        let liveID = live?.id?.uuidString

        // Ended activities linger in `activities` until dismissed; only
        // active ones count, so a resumed dinner starts a fresh one.
        let active = Activity<LiveDinnerAttributes>.activities.filter { $0.activityState == .active }
        for activity in active where activity.attributes.mealID != liveID {
            // Leave the final faces up for a bit, then go.
            Task { await activity.end(activity.content, dismissalPolicy: .after(.now.addingTimeInterval(15 * 60))) }
        }
        guard let live, let liveID, let startedAt = live.liveAt else {
            removeLiveThumbnails()
            return
        }

        let state = LiveDinnerAttributes.ContentState(
            dish: live.displayName,
            cook: live.cook.flatMap { $0.isEmpty ? nil : $0 },
            people: live.tablePeople,
            photoCount: live.sortedPhotos.count,
            me: store.myName,
            photoFile: writeThumbnail(of: live, id: liveID)
        )
        // Other phones only hear "That's dinner" when iCloud wakes them; past
        // the evening's end the Lock Screen says so itself.
        let content = ActivityContent(state: state, staleDate: LiveDinner.endsAt(startedAt))

        if let existing = active.first(where: { $0.attributes.mealID == liveID }) {
            guard existing.content.state != state else { return }
            Task { await existing.update(content) }
            return
        }
        // Live Activities can only be started from the foreground.
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              UIApplication.shared.applicationState == .active
        else { return }
        do {
            _ = try Activity.request(
                attributes: LiveDinnerAttributes(mealID: liveID, startedAt: startedAt),
                content: content
            )
        } catch {
            logger.error("Starting the live dinner failed: \(error.localizedDescription)")
        }
    }
}
