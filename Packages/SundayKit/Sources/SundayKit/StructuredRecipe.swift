import Foundation

/// A recipe sorted into ingredients and steps (by the on-device model, from
/// what the cook said). Kept beside the prose so the Book, and one day a
/// public recipe card, can lay it out properly.
public struct StructuredRecipe: Codable, Equatable, Sendable {
    public var ingredients: [String]
    public var steps: [String]
    public var note: String

    public init(ingredients: [String], steps: [String], note: String = "") {
        self.ingredients = ingredients.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.steps = steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isEmpty: Bool { ingredients.isEmpty && steps.isEmpty }

    /// The readable text version, shown and edited as the recipe.
    public var formatted: String {
        var parts: [String] = []
        if !ingredients.isEmpty {
            parts.append("Ingredients\n" + ingredients.map { "• \($0)" }.joined(separator: "\n"))
        }
        if !steps.isEmpty {
            parts.append("Steps\n" + steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        }
        if !note.isEmpty { parts.append("“\(note)”") }
        return parts.joined(separator: "\n\n")
    }

    public var encoded: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    public static func decode(_ stored: String?) -> StructuredRecipe? {
        guard let data = stored?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StructuredRecipe.self, from: data)
    }

    /// The on-device model has a small context window: about this much
    /// spoken text, plus the answer, fits.
    public static let maxInputCharacters = 6_000
}
