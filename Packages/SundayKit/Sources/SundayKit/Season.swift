import Foundation

public enum Hemisphere: String, CaseIterable, Codable, Sendable {
    case northern
    case southern
}

/// Meteorological seasons: whole months, which is how families actually think
/// about "fall food" vs "summer food".
public enum Season: String, CaseIterable, Codable, Sendable, Identifiable {
    case spring
    case summer
    case fall
    case winter

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .spring: "Spring"
        case .summer: "Summer"
        case .fall: "Fall"
        case .winter: "Winter"
        }
    }

    public var emoji: String {
        switch self {
        case .spring: "🌱"
        case .summer: "☀️"
        case .fall: "🍂"
        case .winter: "❄️"
        }
    }

    public static func of(
        _ date: Date,
        calendar: Calendar = .current,
        hemisphere: Hemisphere = .northern
    ) -> Season {
        let month = calendar.component(.month, from: date)
        let northern: Season = switch month {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .fall
        default: .winter
        }
        return hemisphere == .northern ? northern : northern.opposite
    }

    public var opposite: Season {
        switch self {
        case .spring: .fall
        case .summer: .winter
        case .fall: .spring
        case .winter: .summer
        }
    }
}
