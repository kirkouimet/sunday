import Foundation

/// The small settings file Sunday reads from its own site on launch. It is
/// the one thing an old build can still be told after it ships: "you're too
/// old, update". Nothing about the person or the phone is sent to fetch it.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Builds older than this stop and ask for an update, e.g. "1.2".
    public var minimumVersion: String?
    /// Shown on the update screen instead of the stock line.
    public var message: String?
    /// Where "Update" goes (the App Store or TestFlight page).
    public var updateURL: URL?

    public init(minimumVersion: String? = nil, message: String? = nil, updateURL: URL? = nil) {
        self.minimumVersion = minimumVersion
        self.message = message
        self.updateURL = updateURL
    }

    public static let url = URL(string: "https://www.sunday.cooking/api/app.json")!

    /// True when `version` is older than the minimum. A missing or unreadable
    /// minimum never blocks: a broken file must not lock the family out.
    public func requiresUpdate(from version: String) -> Bool {
        guard let minimumVersion, let minimum = Self.parts(minimumVersion), let current = Self.parts(version)
        else { return false }
        for index in 0 ..< max(minimum.count, current.count) {
            let wanted = index < minimum.count ? minimum[index] : 0
            let have = index < current.count ? current[index] : 0
            if have != wanted { return have < wanted }
        }
        return false
    }

    /// "1.2.0" as [1, 2, 0]; nil unless every part is a number.
    static func parts(_ version: String) -> [Int]? {
        let pieces = version.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        let numbers = pieces.compactMap { Int($0) }
        return numbers.count == pieces.count && !numbers.isEmpty && numbers.allSatisfy { $0 >= 0 } ? numbers : nil
    }
}
