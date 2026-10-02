import AppIntents
import SundayKit
import WidgetKit

/// A star tapped on the widget: queued for the app to save as your private
/// rating, so Monday-morning rating needs no app launch.
struct RateDinnerIntent: AppIntent {
    static var title: LocalizedStringResource = "Rate dinner"
    static var description = IntentDescription("Give last Sunday's dinner your private stars.")

    @Parameter(title: "Dinner") var mealID: String
    @Parameter(title: "Stars") var stars: Int

    init() {}

    init(mealID: UUID, stars: Int) {
        self.mealID = mealID.uuidString
        self.stars = stars
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: mealID) else { return .result() }
        try PendingRatings.add(.init(mealID: id, stars: max(1, min(5, stars))))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
