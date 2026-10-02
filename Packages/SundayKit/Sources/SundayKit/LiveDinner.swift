import Foundation

/// Sunday Live: the evening as it happens. Someone taps "We're sitting
/// down", and for the next few hours everyone in the family can check in
/// ("I'm here") and add their own photos to the same dinner.
public enum LiveDinner {
    /// How long a dinner stays live if nobody wraps it up.
    public static let window: TimeInterval = 5 * 3600

    public static func isLive(startedAt: Date?, endedAt: Date?, now: Date = .now,
                              calendar: Calendar = .current) -> Bool {
        guard let startedAt, endedAt == nil else { return false }
        let elapsed = now.timeIntervalSince(startedAt)
        return elapsed >= -60 && now < endsAt(startedAt, calendar: calendar)
    }

    /// When a dinner nobody wrapped up ends on its own: five hours on, or
    /// 11:30 that night, whichever is first (but never under 90 minutes).
    public static func endsAt(_ startedAt: Date, calendar: Calendar = .current) -> Date {
        let byWindow = startedAt.addingTimeInterval(window)
        guard let lateNight = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: startedAt) else { return byWindow }
        return max(min(byWindow, lateNight), startedAt.addingTimeInterval(90 * 60))
    }

    /// "Mom's cooking · 4 at the table · 3 photos"
    public static func status(cook: String?, people: Int, photos: Int) -> String {
        var parts: [String] = []
        if let cook = cook?.trimmingCharacters(in: .whitespaces), !cook.isEmpty { parts.append("\(cook)'s cooking") }
        if people > 0 { parts.append("\(people) at the table") }
        if photos > 0 { parts.append(photos == 1 ? "1 photo" : "\(photos) photos") }
        return parts.joined(separator: " · ")
    }

    /// Adds a person to the table once (case-insensitively).
    public static func checkIn(_ name: String, to stored: String?) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var people = Attendance.decode(stored)
        guard !trimmed.isEmpty,
              !people.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return Attendance.encode(people) }
        people.append(trimmed)
        return Attendance.encode(people)
    }
}

/// "I'm here" tapped on a Live Activity or a notification. Like widget
/// ratings, queued in the App Group and applied by the app.
public enum PendingCheckIns {
    public struct Entry: Codable, Equatable, Sendable {
        public var mealID: UUID
        public var at: Date

        public init(mealID: UUID, at: Date = .now) {
            self.mealID = mealID
            self.at = at
        }
    }

    private static let fileName = "pending-checkins.json"

    public static func read(from directory: URL? = WidgetStorage.directory) -> [Entry] {
        guard let url = directory?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries
    }

    public static func add(_ entry: Entry, to directory: URL? = WidgetStorage.directory) throws {
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var entries = read(from: directory).filter { $0.mealID != entry.mealID }
        entries.append(entry)
        try JSONEncoder().encode(entries).write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    public static func contains(_ mealID: UUID, in directory: URL? = WidgetStorage.directory) -> Bool {
        read(from: directory).contains { $0.mealID == mealID }
    }

    /// Hands each queued check-in to `apply`, which returns false if it
    /// can't place it yet (the dinner hasn't synced to this phone). Those
    /// stay queued, until they're older than a dinner could last.
    public static func drain(from directory: URL? = WidgetStorage.directory, now: Date = .now,
                             apply: (Entry) -> Bool) {
        let entries = read(from: directory)
        guard !entries.isEmpty, let directory else { return }
        let kept = entries.filter { entry in
            guard now.timeIntervalSince(entry.at) < LiveDinner.window else { return false }
            return !apply(entry)
        }
        let url = directory.appendingPathComponent(fileName)
        if kept.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try? JSONEncoder().encode(kept).write(to: url, options: .atomic)
        }
    }
}
