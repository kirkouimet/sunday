import Foundation

/// What the home-screen widget shows. The app writes it to the shared App
/// Group container; the widget only ever reads it (widgets can't run the
/// CloudKit-backed store themselves).
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public var title: String
        public var caption: String
        public var date: Date
        /// File name of a JPEG thumbnail next to the snapshot, if any.
        public var imageFileName: String?
        /// `sunday://meal/<uuid>` for tapping through.
        public var mealID: UUID

        public init(title: String, caption: String, date: Date, imageFileName: String?, mealID: UUID) {
            self.title = title
            self.caption = caption
            self.date = date
            self.imageFileName = imageFileName
            self.mealID = mealID
        }
    }

    public var latest: Item?
    public var memory: Item?
    public var streak: Int
    public var totalDinners: Int
    public var generatedAt: Date

    public init(latest: Item?, memory: Item?, streak: Int, totalDinners: Int, generatedAt: Date = .now) {
        self.latest = latest
        self.memory = memory
        self.streak = streak
        self.totalDinners = totalDinners
        self.generatedAt = generatedAt
    }

    public static let empty = WidgetSnapshot(latest: nil, memory: nil, streak: 0, totalDinners: 0)
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

        // Replace old thumbnails so the container doesn't grow forever.
        let keep = Set(images.keys).union([fileName])
        for existing in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? [] where !keep.contains(existing) {
            try? fm.removeItem(at: directory.appendingPathComponent(existing))
        }
        for (name, data) in images {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
        try encoder.encode(snapshot).write(to: directory.appendingPathComponent(fileName), options: .atomic)
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

    public static func mealID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == "meal" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
