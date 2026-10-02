import Foundation

/// One colour per person, the same in the app, the widget and the Live
/// Activity, so Ellie is always green.
public enum AvatarPalette {
    public static let colors: [(red: Double, green: Double, blue: Double)] = [
        (0.84, 0.45, 0.27), (0.36, 0.55, 0.42), (0.38, 0.47, 0.70),
        (0.66, 0.42, 0.62), (0.75, 0.58, 0.22), (0.31, 0.58, 0.62),
    ]

    public static func index(for name: String) -> Int {
        let sum = name.trimmingCharacters(in: .whitespaces).lowercased().unicodeScalars
            .reduce(0) { $0 &+ Int($1.value) }
        return abs(sum) % colors.count
    }

    public static func initial(for name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}
