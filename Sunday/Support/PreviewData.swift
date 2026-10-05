import CoreData
import SundayKit
import UIKit

/// Sample dinners for SwiftUI previews, UI tests and App Store screenshots.
enum PreviewData {
    private struct Dinner {
        let name: String
        let weeksAgo: Int
        let stars: Int?
        let notes: String
        let symbol: String
        let colors: (UIColor, UIColor)
        var photoCount = 1
        var tags: [String] = []
        var attendees: [String] = ["Mom", "Dad", "Ellie"]
        var recipe: String? = nil
    }

    private static let dinners: [Dinner] = [
        Dinner(name: "Lemon chicken & roasted potatoes", weeksAgo: 0, stars: nil, notes: "Grandma came over.",
               symbol: "fork.knife", colors: (.systemOrange, .systemYellow), photoCount: 3, tags: ["chicken", "potato"],
               attendees: ["Mom", "Dad", "Ellie", "Grandma June"]),
        Dinner(name: "Butternut squash soup", weeksAgo: 1, stars: 4, notes: "",
               symbol: "cup.and.saucer.fill", colors: (.systemOrange, .systemBrown), tags: ["soup"]),
        Dinner(name: "Homemade pizza night", weeksAgo: 2, stars: 5, notes: "Kids made their own.",
               symbol: "flame.fill", colors: (.systemRed, .systemOrange), photoCount: 2,
               attendees: ["Mom", "Dad", "Ellie", "Sam"]),
        Dinner(name: "Salmon with rice", weeksAgo: 3, stars: 4, notes: "",
               symbol: "fish.fill", colors: (.systemPink, .systemOrange)),
        Dinner(name: "Pot roast", weeksAgo: 10, stars: 5, notes: "",
               symbol: "frying.pan.fill", colors: (.brown, .systemOrange)),
        Dinner(name: "Tacos", weeksAgo: 14, stars: 4, notes: "",
               symbol: "takeoutbag.and.cup.and.straw.fill", colors: (.systemYellow, .systemGreen)),
        Dinner(name: "Spaghetti & meatballs", weeksAgo: 52, stars: 5, notes: "Perfect for the first cold Sunday.",
               symbol: "fork.knife", colors: (.systemRed, .brown)),
        Dinner(name: "Lemon chicken & roasted potatoes", weeksAgo: 60, stars: 4, notes: "",
               symbol: "fork.knife", colors: (.systemOrange, .systemYellow),
               recipe: "1 whole chicken, 2 lemons, 2 lb small potatoes, garlic, thyme.\n\nPotatoes in first at 425°F for 15 minutes. Chicken on top with lemon halves and garlic, 55 more minutes. Squeeze the roasted lemon over everything."),
        Dinner(name: "Thanksgiving turkey", weeksAgo: 45, stars: 5, notes: "Everyone was here.",
               symbol: "leaf.fill", colors: (.systemBrown, .systemOrange)),
        Dinner(name: "Birthday lasagna", weeksAgo: 30, stars: 5, notes: "",
               symbol: "birthday.cake.fill", colors: (.systemPurple, .systemPink)),
    ]

    /// Each dish's photo file ("lemon-chicken-1.jpg") and the line the
    /// on-device model would write for it.
    private static let seen: [String: (photo: String, caption: String)] = [
        "Lemon chicken & roasted potatoes": ("lemon-chicken", "Roast chicken with golden potato wedges."),
        "Butternut squash soup": ("squash-soup", "A bowl of squash soup with seeds and cheese."),
        "Homemade pizza night": ("pizza", "A homemade pizza with tomato slices and olives."),
        "Salmon with rice": ("salmon", "Salmon with rice and lemon on a plate."),
        "Pot roast": ("pot-roast", "Pot roast with green beans and mashed potatoes."),
        "Tacos": ("tacos", "Three tacos with meat, onion and cilantro."),
        "Spaghetti & meatballs": ("spaghetti", "Spaghetti and meatballs with grated cheese."),
        "Thanksgiving turkey": ("turkey", "A roast turkey in the pan."),
        "Birthday lasagna": ("lasagna", "A slice of lasagna with melted cheese."),
    ]

    /// App Store screenshots use real photos: point SUNDAY_SAMPLE_PHOTOS at a
    /// folder of "<dish>-<n>.jpg" (see AppStore/SamplePhotos). Without it, or
    /// for a dish with no file, the drawn plate stands in.
    private static func samplePhoto(for dish: String, index: Int) -> UIImage? {
        guard let folder = ProcessInfo.processInfo.environment["SUNDAY_SAMPLE_PHOTOS"],
              let name = seen[dish]?.photo
        else { return nil }
        return UIImage(contentsOfFile: "\(folder)/\(name)-\(index + 1).jpg")
    }

    static func populate(_ context: NSManagedObjectContext) {
        let calendar = Calendar.current
        let lastSunday = calendar.date(bySettingHour: 18, minute: 30, second: 0,
                                       of: SundayCalendar.mostRecentSunday(onOrBefore: .now)) ?? .now

        for dinner in dinners {
            let date = calendar.date(byAdding: .day, value: -7 * dinner.weeksAgo, to: lastSunday) ?? lastSunday
            let meal = Meal(context: context)
            meal.id = UUID()
            meal.name = dinner.name
            meal.date = date
            meal.cook = dinner.weeksAgo == 2 ? "Dad" : "Mom"
            meal.notes = dinner.notes
            meal.createdAt = date
            meal.tags = dinner.tags.isEmpty ? nil : FoodTags.encode(dinner.tags)
            meal.attendees = Attendance.encode(dinner.attendees)
            meal.recipe = dinner.recipe
            meal.caption = seen[dinner.name]?.caption

            for index in 0..<dinner.photoCount {
                let image = samplePhoto(for: dinner.name, index: index)
                    ?? illustration(symbol: dinner.symbol, colors: dinner.colors, variant: index)
                let photo = Photo(context: context)
                photo.id = UUID()
                photo.createdAt = date
                photo.sortIndex = Int16(index)
                photo.imageData = image.jpegData(compressionQuality: 0.8)
                photo.thumbnailData = photo.imageData
                photo.meal = meal
            }

            if let stars = dinner.stars {
                let rating = Rating(context: context)
                rating.id = UUID()
                rating.mealID = meal.id
                rating.stars = Int16(stars)
                rating.updatedAt = date
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-uiLive") {
            addLiveDinner(context)
        }
        try? context.save()
    }

    /// Sunday Live in progress, for screenshots: Dad's spaghetti, two photos so
    /// far, and this phone (Grandma June's) not checked in yet.
    private static func addLiveDinner(_ context: NSManagedObjectContext) {
        let started = Date.now.addingTimeInterval(-25 * 60)
        let meal = Meal(context: context)
        meal.id = UUID()
        meal.name = "Spaghetti & meatballs"
        meal.date = started
        meal.createdAt = started
        meal.cook = "Dad"
        meal.attendees = Attendance.encode(["Dad", "Mom", "Ellie"])
        meal.liveAt = started
        meal.liveBy = "Dad"
        for index in 0..<2 {
            let photo = Photo(context: context)
            photo.id = UUID()
            photo.createdAt = started
            photo.sortIndex = Int16(index)
            photo.by = index == 0 ? "Dad" : "Ellie"
            photo.createdAt = started.addingTimeInterval(Double(index) * 600)
            photo.imageData = (samplePhoto(for: "Spaghetti & meatballs", index: 0)
                ?? illustration(symbol: "fork.knife", colors: (.systemRed, .brown), variant: index))
                .jpegData(compressionQuality: 0.8)
            photo.thumbnailData = photo.imageData
            photo.meal = meal
        }
        UserDefaults.standard.set("Grandma June", forKey: "myName")
    }

    private static func illustration(symbol: String, colors: (UIColor, UIColor), variant: Int) -> UIImage {
        let size = CGSize(width: 800, height: 600)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [colors.0.cgColor, colors.1.cgColor] as CFArray,
                                      locations: [0, 1])!
            let angle = CGFloat(variant) * 0.6
            cg.drawLinearGradient(gradient,
                                  start: CGPoint(x: 0, y: size.height * angle / 2),
                                  end: CGPoint(x: size.width, y: size.height),
                                  options: [])

            // A plate with the dish icon on it.
            let plate = CGRect(x: size.width / 2 - 190, y: size.height / 2 - 190, width: 380, height: 380)
            UIColor.white.withAlphaComponent(0.92).setFill()
            UIBezierPath(ovalIn: plate).fill()
            UIColor.black.withAlphaComponent(0.06).setStroke()
            let rim = UIBezierPath(ovalIn: plate.insetBy(dx: 40, dy: 40))
            rim.lineWidth = 6
            rim.stroke()

            let config = UIImage.SymbolConfiguration(pointSize: 150, weight: .semibold)
            if let icon = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(colors.0.withAlphaComponent(0.9), renderingMode: .alwaysOriginal) {
                let iconSize = icon.size
                icon.draw(in: CGRect(x: plate.midX - iconSize.width / 2, y: plate.midY - iconSize.height / 2,
                                     width: iconSize.width, height: iconSize.height))
            }
        }
    }
}
