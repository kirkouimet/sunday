import Foundation

/// What the home-screen widget shows. The app writes it to the shared App
/// Group container; the widget only ever reads it (widgets can't run the
/// CloudKit-backed store themselves). It holds dates, not captions, so the
/// widget can say "Tonight" / "A year ago this week" correctly on any day.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public var title: String
        public var date: Date
        /// File name of a JPEG thumbnail next to the snapshot, if any.
        public var imageFileName: String?
        public var mealID: UUID

        public init(title: String, date: Date, imageFileName: String?, mealID: UUID) {
            self.title = title
            self.date = date
            self.imageFileName = imageFileName
            self.mealID = mealID
        }
    }

    public var latest: Item?
    /// Past-year dinners near the coming days; the widget picks per day.
    public var memories: [Item]
    /// Recent dinner dates, for computing the streak on any day.
    public var recentDates: [Date]
    public var totalDinners: Int
    public var generatedAt: Date
    /// This Sunday's plan ("Chili"), and who's cooking it, for the Lock Screen.
    public var plan: Item?
    public var planCook: String?
    /// Last Sunday's dinner, while you haven't rated it: the widget asks
    /// "How was Chili?" with five tappable stars.
    public var toRate: Item?

    public init(latest: Item?, memories: [Item], recentDates: [Date], totalDinners: Int,
                generatedAt: Date = .now, plan: Item? = nil, planCook: String? = nil, toRate: Item? = nil) {
        self.toRate = toRate
        self.latest = latest
        self.memories = memories
        self.recentDates = recentDates
        self.totalDinners = totalDinners
        self.generatedAt = generatedAt
        self.plan = plan
        self.planCook = planCook
    }

    /// "Tonight: Chili · Dad's cooking" / "Sunday: Chili", or nil once it's past.
    public func planLine(on day: Date, calendar: Calendar = .current) -> String? {
        guard let plan, calendar.startOfDay(for: plan.date) >= calendar.startOfDay(for: day) else { return nil }
        let when = calendar.isDate(plan.date, inSameDayAs: day) ? "Tonight" : "Sunday"
        let cook = planCook.map { " · \($0)'s cooking" } ?? ""
        return "\(when): \(plan.title)\(cook)"
    }

    public static let empty = WidgetSnapshot(latest: nil, memories: [], recentDates: [], totalDinners: 0,
                                             generatedAt: Date(timeIntervalSince1970: 0))

    /// Same content, ignoring when it was generated.
    public func hasSameContent(as other: WidgetSnapshot) -> Bool {
        var a = self, b = other
        a.generatedAt = .distantPast
        b.generatedAt = .distantPast
        return a == b
    }

    // MARK: Per-day presentation

    /// The "this week in years past" dinner for `day`, if any.
    public func memory(on day: Date, calendar: Calendar = .current) -> Item? {
        let summaries = memories.map { MealSummary(id: $0.mealID, name: $0.title, date: $0.date, stars: nil) }
        guard let pick = Suggestions(meals: summaries, now: day, calendar: calendar).thisTimeInPastYears(windowDays: 7).first
        else { return nil }
        let item = memories.first { $0.mealID == pick.id }
        return item?.mealID == latest?.mealID ? nil : item
    }

    public func streak(on day: Date, calendar: Calendar = .current) -> Int {
        SundayCalendar.streak(mealDates: recentDates, now: day, calendar: calendar)
    }

    public static func latestCaption(for date: Date, on day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: day) { return "Tonight" }
        if SundayCalendar.isSunday(date, calendar: calendar),
           calendar.isDate(date, inSameDayAs: SundayCalendar.mostRecentSunday(onOrBefore: day, calendar: calendar)) {
            return "Last Sunday"
        }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    public static func memoryCaption(for date: Date, on day: Date, calendar: Calendar = .current) -> String {
        let years = SundayCalendar.yearsAgo(date, now: day, calendar: calendar)
        return years == 1 ? "A year ago this week" : "\(years) years ago this week"
    }
}

public enum WidgetStorage {
    public static let appGroupID = "group.com.kirkouimet.sunday"
    private static let fileName = "widget-snapshot.json"

    public static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Widget", isDirectory: true)
    }

    public static func read(from directory: URL? = directory) -> WidgetSnapshot {
        guard let url = directory?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    public static func write(_ snapshot: WidgetSnapshot, images: [String: Data], to directory: URL? = directory) throws {
        guard let directory else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        for (name, data) in images where !fm.fileExists(atPath: directory.appendingPathComponent(name).path) {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
        try encoder.encode(snapshot).write(to: directory.appendingPathComponent(fileName), options: .atomic)

        // Only now remove thumbnails the new snapshot no longer uses, so the
        // widget never reads a snapshot pointing at a deleted image.
        // Only widget thumbnails: the queues (pending ratings, check-ins) and
        // the live dinner's photo live here too.
        let keep = Set(images.keys)
        for existing in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        where existing.hasSuffix(".jpg") && !existing.hasPrefix("live-") && !keep.contains(existing) {
            try? fm.removeItem(at: directory.appendingPathComponent(existing))
        }
    }

    public static func imageData(named name: String?, in directory: URL? = directory) -> Data? {
        guard let name, let directory else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum DeepLink {
    public static let scheme = "sunday"

    public static func url(forMeal id: UUID) -> URL {
        URL(string: "\(scheme)://meal/\(id.uuidString)")!
    }

    /// Opens the camera for tonight's dinner.
    public static let snap = URL(string: "sunday://snap")!
    /// Opens the feed to the live dinner ("Tell the table").
    public static let live = URL(string: "sunday://live")!

    public static func isSnap(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == "snap"
    }

    public static func mealID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == "meal" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
