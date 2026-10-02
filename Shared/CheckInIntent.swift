import AppIntents
import Foundation
import SundayKit

/// "I'm here", tapped on the Live Activity. Live Activity intents run in
/// the app's process; the check-in is queued in the App Group first so it
/// survives even if the app isn't fully up yet.
struct CheckInIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "I'm at the table"
    static var description = IntentDescription("Check in to Sunday dinner.")

    @Parameter(title: "Dinner") var mealID: String

    /// Set by the app so a check-in is applied right away.
    @MainActor static var onCheckIn: (@MainActor () -> Void)?

    init() {}

    init(mealID: UUID) {
        self.mealID = mealID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: mealID) else { return .result() }
        try PendingCheckIns.add(.init(mealID: id))
        await MainActor.run { Self.onCheckIn?() }
        return .result()
    }
}

/// "I'm here" on a phone that hasn't said whose it is yet: opens the app,
/// which asks "Which one are you?" and then checks in.
struct CheckInAndAskIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "I'm at the table"
    static var openAppWhenRun = true

    @Parameter(title: "Dinner") var mealID: String

    init() {}

    init(mealID: UUID) {
        self.mealID = mealID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: mealID) else { return .result() }
        try PendingCheckIns.add(.init(mealID: id))
        return .result()
    }
}
