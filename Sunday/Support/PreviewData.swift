import CoreData
import UIKit

/// Sample dinners for SwiftUI previews and the in-memory store.
enum PreviewData {
    static func populate(_ context: NSManagedObjectContext) {
        let calendar = Calendar.current
        let dinners: [(String, Int, Int?, String)] = [
            ("Lemon chicken & roasted potatoes", 0, 5, "Extra lemon next time."),
            ("Butternut squash soup", 7, 4, ""),
            ("Homemade pizza night", 14, 5, "Kids made their own."),
            ("Pot roast", 70, 4, ""),
            ("Chili", 360, 5, "Perfect for the first cold Sunday."),
            ("Lemon chicken & roasted potatoes", 400, 4, ""),
        ]
        let colors: [UIColor] = [.systemOrange, .systemYellow, .systemRed, .brown, .systemPink, .systemOrange]

        for (index, dinner) in dinners.enumerated() {
            let meal = Meal(context: context)
            meal.id = UUID()
            meal.name = dinner.0
            meal.date = calendar.date(byAdding: .day, value: -dinner.1, to: .now)
            meal.cook = "Mom"
            meal.notes = dinner.3
            meal.createdAt = meal.date

            let photo = Photo(context: context)
            photo.id = UUID()
            photo.createdAt = meal.date
            photo.thumbnailData = swatch(colors[index]).jpegData(compressionQuality: 0.7)
            photo.imageData = photo.thumbnailData
            photo.meal = meal

            if let stars = dinner.2 {
                let rating = Rating(context: context)
                rating.id = UUID()
                rating.mealID = meal.id
                rating.stars = Int16(stars)
                rating.updatedAt = .now
            }
        }
        try? context.save()
    }

    private static func swatch(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 600, height: 450)
        return UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
