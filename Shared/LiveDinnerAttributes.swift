import ActivityKit
import Foundation

/// The Live Activity for a Sunday dinner in progress: on the Lock Screen
/// and in the Dynamic Island of everyone at the table.
struct LiveDinnerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var dish: String
        var cook: String?
        /// Who has checked in, in order.
        var people: [String]
        var photoCount: Int
        /// Whoever this phone belongs to, so "I'm here" turns into a check mark.
        var me: String?
        /// The newest photo's thumbnail in the App Group, if any.
        var photoFile: String?

        var isMeCheckedIn: Bool {
            guard let me else { return false }
            return people.contains { $0.caseInsensitiveCompare(me) == .orderedSame }
        }
    }

    var mealID: String
    var startedAt: Date
}
