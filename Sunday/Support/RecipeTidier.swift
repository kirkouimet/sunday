import Foundation
import SundayKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Talk instead of type: Apple's on-device model turns a rambling spoken
/// recipe into ingredients and steps, in the cook's own words. Nothing
/// leaves the phone, and nothing is invented.
enum RecipeTidier {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    enum Outcome {
        case sorted(StructuredRecipe)
        /// More than the on-device model can take in at once.
        case tooLong
        case failed
    }

    /// Long tellings (Grandma's ten minutes) are sorted a piece at a time
    /// and merged: ingredients once, steps in order.
    static func tidy(_ text: String, dish: String) async -> Outcome {
        let pieces = StructuredRecipe.chunks(of: text)
        guard pieces.count <= 4 else { return .tooLong }
        var sorted: [StructuredRecipe] = []
        for (index, piece) in pieces.enumerated() {
            switch await tidyPiece(piece, dish: dish, part: pieces.count > 1 ? (index + 1, pieces.count) : nil) {
            case .sorted(let recipe): sorted.append(recipe)
            case .tooLong: return .tooLong
            case .failed: continue
            }
        }
        let merged = StructuredRecipe.merged(sorted)
        return merged.isEmpty ? .failed : .sorted(merged)
    }

    private static func tidyPiece(_ text: String, dish: String, part: (Int, Int)?) async -> Outcome {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // A fresh session per piece, so each fits the context window.
            let session = LanguageModelSession(instructions: """
                You turn a family member's spoken description of how they cook a dish into a tidy \
                recipe card. Keep their words, quantities and asides. Never add an ingredient, \
                amount or step they did not say. If they gave no amount, leave it out.
                """)
            let partNote = part.map { "\n(This is part \($0.0) of \($0.1) of what they said.)" } ?? ""
            do {
                let response = try await session.respond(
                    to: "Dish: \(dish)\(partNote)\n\nWhat they said:\n\(text)",
                    generating: TidyRecipe.self
                )
                let recipe = StructuredRecipe(ingredients: response.content.ingredients,
                                              steps: response.content.steps,
                                              note: response.content.note)
                return recipe.isEmpty ? .failed : .sorted(recipe)
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error { return .tooLong }
                return .failed
            } catch {
                return .failed
            }
        }
        #endif
        return .failed
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct TidyRecipe {
    @Guide(description: "Each ingredient they mentioned, with the amount if they said one")
    var ingredients: [String]
    @Guide(description: "The steps in order, short, in the cook's own words")
    var steps: [String]
    @Guide(description: "A tip, memory or family note they mentioned, or an empty string")
    var note: String
}
#endif
