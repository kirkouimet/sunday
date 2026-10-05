import Foundation

/// What the on-device model saw in a dinner photo: a name to offer and one
/// line saying what's on the table. Tidied here so the model's habits
/// (Title Case, quotes, a stray full stop) never reach the family's record.
public struct MealDescription: Equatable, Sendable {
    public var name: String
    public var caption: String

    public init(name: String, caption: String) {
        self.name = name
        self.caption = caption
    }

    /// Nil when the photo isn't food or the model had nothing usable to say.
    public static func cleaned(name: String, caption: String, isFood: Bool) -> MealDescription? {
        let name = sentenceCased(stripped(name, dropping: ".!"))
        guard isFood, !name.isEmpty, name.count <= 60 else { return nil }
        var caption = stripped(caption, dropping: "")
        if caption.count > 160 { caption = "" }
        if !caption.isEmpty, let last = caption.last, !".!?".contains(last) { caption += "." }
        return MealDescription(name: name, caption: caption)
    }

    private static func stripped(_ text: String, dropping trailing: String) -> String {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
        while let last = text.last, trailing.contains(last) { text.removeLast() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Spaghetti with Meat Sauce" → "Spaghetti with meat sauce", the way
    /// the family types dinners. Words in capitals ("BBQ") are left alone.
    static func sentenceCased(_ text: String) -> String {
        let words = text.split(separator: " ").enumerated().map { index, word -> String in
            let word = String(word)
            if word.count > 1, word == word.uppercased() { return word }
            return index == 0 ? word.prefix(1).uppercased() + word.dropFirst() : word.lowercased()
        }
        return words.joined(separator: " ")
    }
}
