import SundayKit
import Vision

/// Classifies a dinner photo on device. Nothing leaves the phone.
enum FoodTagger {
    static func tags(forJPEG data: Data) async -> [String] {
        await Task.detached(priority: .utility) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(data: data)
            do {
                try handler.perform([request])
            } catch {
                return []
            }
            let observations = (request.results ?? []).map { (identifier: $0.identifier, confidence: $0.confidence) }
            return FoodTags.tags(from: observations)
        }.value
    }
}
