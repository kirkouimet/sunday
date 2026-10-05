import ImageIO
import SundayKit
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Looks at a dinner photo and says what the food is: a name to offer while
/// you're typing, and one line for the dinner's page and for search. It runs
/// on Apple's on-device model (iOS 27), so the photo never leaves the phone.
/// Phones without it simply don't offer anything.
enum MealDescriber {
    enum Outcome {
        case described(MealDescription)
        /// The model looked and it isn't dinner: don't ask again.
        case notFood
        /// Couldn't look this time (busy, interrupted): worth another try.
        case failed
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability { return model.capabilities.contains(.vision) }
        }
        #endif
        return false
    }

    static func describe(_ image: UIImage) async -> Outcome {
        guard isAvailable else { return .failed }
        let data = await Task.detached(priority: .utility) { image.jpegData(compressionQuality: 0.7) }.value
        guard let data else { return .failed }
        return await describe(jpeg: data)
    }

    static func describe(jpeg data: Data) async -> Outcome {
        #if canImport(FoundationModels) && compiler(>=6.4)
        if #available(iOS 27.0, *) {
            guard isAvailable, let image = downsized(data) else { return .failed }
            let session = LanguageModelSession(instructions: """
                You look at a photo from a family's Sunday dinner and say what the food is. \
                Describe only food you can see. Never mention people, places or brands, and never \
                guess at ingredients you can't see.
                """)
            do {
                let seen = try await session.respond(generating: SeenDinner.self) {
                    "What is this dinner?"
                    Attachment(image)
                }.content
                guard let description = MealDescription.cleaned(name: seen.name, caption: seen.caption, isFood: seen.isFood)
                else { return .notFood }
                return .described(description)
            } catch {
                return .failed
            }
        }
        #endif
        return .failed
    }

    /// The model doesn't need 2048 pixels to recognise lasagna.
    private static func downsized(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
        ] as CFDictionary)
    }
}

#if canImport(FoundationModels) && compiler(>=6.4)
@available(iOS 27.0, *)
@Generable
struct SeenDinner {
    @Guide(description: "True only if the photo shows food or a meal")
    var isFood: Bool
    @Guide(description: "The dish as a family would name it, two to five words, like 'Lemon chicken and potatoes'. Empty if the photo isn't food.")
    var name: String
    @Guide(description: "One plain sentence, under twenty words, saying what food is on the table. Empty if the photo isn't food.")
    var caption: String
}
#endif
