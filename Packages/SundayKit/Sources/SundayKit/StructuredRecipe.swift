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
    /// spoken text, plus the answer, fits in one go.
    public static let maxInputCharacters = 5_000

    /// Splits a long telling at sentence ends into pieces the model can take.
    public static func chunks(of text: String, max: Int = maxInputCharacters) -> [String] {
        guard text.count > max else { return [text] }
        var chunks: [String] = []
        var current = ""
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { _, _, enclosing, _ in
            let sentence = String(text[enclosing])
            if current.count + sentence.count > max, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += sentence
        }
        if !current.isEmpty { chunks.append(current) }
        // A single sentence longer than max still goes, cut hard.
        return chunks.flatMap { chunk -> [String] in
            guard chunk.count > max else { return [chunk] }
            return stride(from: 0, to: chunk.count, by: max).map { start in
                let from = chunk.index(chunk.startIndex, offsetBy: start)
                let to = chunk.index(from, offsetBy: Swift.min(max, chunk.count - start))
                return String(chunk[from..<to])
            }
        }
    }

    /// Sorted pieces back into one card: ingredients once, steps in order.
    public static func merged(_ parts: [StructuredRecipe]) -> StructuredRecipe {
        var seen = Set<String>()
        let ingredients = parts.flatMap(\.ingredients).filter { seen.insert($0.lowercased()).inserted }
        return StructuredRecipe(ingredients: ingredients,
                                steps: parts.flatMap(\.steps),
                                note: parts.map(\.note).filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// Reads the text version back, so fixing a typo keeps the structure.
    public static func parse(_ text: String) -> StructuredRecipe? {
        var ingredients: [String] = [], steps: [String] = [], notes: [String] = []
        var section = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == "Ingredients" || line == "Steps" { section = line; continue }
            if line.hasPrefix("“"), line.hasSuffix("”") {
                notes.append(String(line.dropFirst().dropLast()))
            } else if section == "Ingredients", line.hasPrefix("•") {
                ingredients.append(String(line.dropFirst()))
            } else if section == "Steps", let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), dot > line.startIndex {
                steps.append(String(line[line.index(after: dot)...]))
            } else if section == "Steps", !steps.isEmpty {
                steps[steps.count - 1] += " " + line
            } else {
                return nil // Not our layout: plain prose stays prose.
            }
        }
        let recipe = StructuredRecipe(ingredients: ingredients, steps: steps, note: notes.joined(separator: " "))
        return recipe.isEmpty ? nil : recipe
    }
}
