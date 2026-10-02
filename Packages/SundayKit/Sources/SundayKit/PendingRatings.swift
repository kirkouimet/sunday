import Foundation

/// Ratings tapped on a widget. Widgets can't open the CloudKit-backed store,
/// so they queue ratings in the App Group; the app applies them (as your
/// private rating) the next time it runs.
public enum PendingRatings {
    public struct Entry: Codable, Equatable, Sendable {
        public var mealID: UUID
        public var stars: Int
        public var at: Date

        public init(mealID: UUID, stars: Int, at: Date = .now) {
            self.mealID = mealID
            self.stars = stars
            self.at = at
        }
    }

    private static let fileName = "pending-ratings.json"

    public static func read(from directory: URL? = WidgetStorage.directory) -> [Entry] {
        guard let url = directory?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries
    }

    /// Adds a rating, replacing any earlier pending one for the same dinner.
    public static func add(_ entry: Entry, to directory: URL? = WidgetStorage.directory) throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var entries = read(from: directory).filter { $0.mealID != entry.mealID }
        entries.append(entry)
        try JSONEncoder().encode(entries).write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    /// The pending stars for a dinner, so the widget can show your tap.
    public static func stars(for mealID: UUID, in directory: URL? = WidgetStorage.directory) -> Int? {
        read(from: directory).last { $0.mealID == mealID }?.stars
    }

    /// Hands every pending rating to `apply` and empties the queue.
    public static func drain(from directory: URL? = WidgetStorage.directory, apply: (Entry) -> Void) {
        let entries = read(from: directory)
        guard !entries.isEmpty, let directory else { return }
        entries.forEach(apply)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }
}
