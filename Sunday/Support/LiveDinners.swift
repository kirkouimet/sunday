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

    static func sync(store: MealStore) {
        guard !PersistenceController.isUITesting else { return }
        let live = store.liveMeal()
        let liveID = live?.id?.uuidString

        for activity in Activity<LiveDinnerAttributes>.activities where activity.attributes.mealID != liveID {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        guard let live, let liveID, let startedAt = live.liveAt else { return }

        let state = LiveDinnerAttributes.ContentState(
            dish: live.displayName,
            cook: live.cook.flatMap { $0.isEmpty ? nil : $0 },
            people: Attendance.decode(live.attendees),
            photoCount: live.sortedPhotos.count,
            me: store.myName
        )
        let content = ActivityContent(state: state, staleDate: startedAt.addingTimeInterval(LiveDinner.window))

        if let existing = Activity<LiveDinnerAttributes>.activities.first(where: { $0.attributes.mealID == liveID }) {
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
