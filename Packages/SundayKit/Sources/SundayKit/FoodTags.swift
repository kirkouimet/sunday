import Foundation

/// Turns on-device image classification results into a few food tags
/// ("pasta", "salad"). Only labels on a food allowlist are kept, so a photo
/// of the kids at the table never gets tagged "child" or "table".
public enum FoodTags {
    /// Vision classifier identifiers that are foods or dish types.
    public static let allowlist: Set<String> = [
        "apple", "avocado", "bagel", "banana", "barbecue", "bean", "berry", "bread", "breakfast", "broccoli",
        "brownie", "burger", "burrito", "cake", "candy", "carrot", "casserole", "cheese", "cheesecake",
        "cherry", "chicken", "chili", "chocolate", "cookie", "corn", "croissant", "cupcake", "curry", "dessert",
        "donut", "dumpling", "egg", "fish", "fries", "fruit", "grape", "grilled", "ham", "hamburger", "hotdog",
        "ice_cream", "lasagna", "lemon", "lobster", "meat", "meatball", "muffin", "mushroom", "noodle", "omelet",
        "orange", "pancake", "pasta", "pastry", "pepper", "pie", "pizza", "pork", "potato", "pudding", "ramen",
        "rice", "roast", "salad", "salmon", "sandwich", "sausage", "seafood", "shrimp", "soup", "spaghetti",
        "steak", "stew", "strawberry", "sushi", "taco", "tomato", "turkey", "vegetable", "waffle",
    ]

    /// Up to `limit` allowed tags, most confident first.
    public static func tags(from observations: [(identifier: String, confidence: Float)],
                            minimumConfidence: Float = 0.3,
                            limit: Int = 3) -> [String] {
        var seen = Set<String>()
        return observations
            .filter { $0.confidence >= minimumConfidence && allowlist.contains($0.identifier) }
            .sorted { $0.confidence > $1.confidence }
            .compactMap { seen.insert($0.identifier).inserted ? $0.identifier : nil }
            .prefix(limit)
            .map { $0 }
    }

    /// Stored on the meal as "pasta,salad".
    public static func encode(_ tags: [String]) -> String { tags.joined(separator: ",") }

    public static func decode(_ stored: String?) -> [String] {
        (stored ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    /// "ice_cream" → "Ice cream".
    public static func displayName(_ tag: String) -> String {
        let spaced = tag.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
