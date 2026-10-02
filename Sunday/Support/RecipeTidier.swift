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

    static func tidy(_ text: String, dish: String) async -> Outcome {
        guard text.count <= StructuredRecipe.maxInputCharacters else { return .tooLong }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(instructions: """
                You turn a family member's spoken description of how they cook a dish into a tidy \
                recipe card. Keep their words, quantities and asides. Never add an ingredient, \
                amount or step they did not say. If they gave no amount, leave it out.
                """)
            do {
                let response = try await session.respond(
                    to: "Dish: \(dish)\n\nWhat they said:\n\(text)",
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
