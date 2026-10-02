import Foundation

/// Who was at the table. Stored on a dinner as "Mom,Dad,Grandma June".
public enum Attendance {
    public static func encode(_ people: [String]) -> String {
        var seen = Set<String>()
        return people
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .joined(separator: ",")
    }

    public static func decode(_ stored: String?) -> [String] {
        (stored ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public struct Dinner: Sendable {
        public let id: UUID
        public let date: Date
        public let people: [String]
        public init(id: UUID, date: Date, people: [String]) {
            self.id = id
            self.date = date
            self.people = people
        }
    }

    public static let milestones: Set<Int> = [10, 25, 50, 100, 150, 200, 250, 300, 400, 500]

    /// The memorable thing about who came to this dinner, if anything:
    /// "First Sunday with June" or "Grandma's 25th Sunday".
    public static func moment(for id: UUID, in dinners: [Dinner]) -> String? {
        let chronological = dinners.sorted { $0.date < $1.date }
        guard let index = chronological.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        let earlier = chronological[..<index]
        let here = chronological[index].people
        let seenBefore = Set(earlier.flatMap(\.people).map { $0.lowercased() })

        if let newcomer = here.first(where: { !seenBefore.contains($0.lowercased()) }) {
            return "First Sunday with \(newcomer)"
        }
        for person in here {
            let count = chronological[...index].filter { $0.people.contains { $0.caseInsensitiveCompare(person) == .orderedSame } }.count
            if milestones.contains(count) {
                return "\(person)'s \(PersonalInsight.ordinalString(count)) Sunday"
            }
        }
        return nil
    }

    /// How many dinners each person has been at, most first.
    public static func counts(in dinners: [Dinner]) -> [(name: String, count: Int)] {
        var tally: [String: (name: String, count: Int)] = [:]
        for person in dinners.flatMap(\.people) {
            tally[person.lowercased(), default: (person, 0)].count += 1
        }
        return tally.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
}
