import SundayKit
import SwiftUI
import UIKit

extension Hemisphere {
    static let storageKey = "hemisphere"

    static var current: Hemisphere {
        UserDefaults.standard.string(forKey: storageKey).flatMap(Hemisphere.init(rawValue:)) ?? .northern
    }
}

extension Meal {
    var season: Season { Season.of(date ?? .now, hemisphere: .current) }
    var holiday: Holiday? { date.flatMap { Holidays.holiday(near: $0) } }

    /// True once the object is gone, locally or because someone else deleted it.
    var isGone: Bool { isDeleted || managedObjectContext == nil }
}

extension Color {
    static let star = Color("StarColor")
    /// Accent for filled backgrounds. Pair with `onAccentFill` text.
    static let accentFill = Color("AccentFill")
    /// White on the light-mode fill, black on the brighter dark-mode fill.
    static let onAccentFill = Color(.systemBackground)
}

func starsDescription(_ stars: Double) -> String {
    if stars == stars.rounded() {
        let whole = Int(stars)
        return "\(whole) of 5 star\(whole == 1 ? "" : "s")"
    }
    return "\(stars.formatted(.number.precision(.fractionLength(1)))) of 5 stars"
}

/// Tap a star to set it; tap the same star again to clear. One adjustable
/// element for VoiceOver (swipe up/down to change).
struct StarRatingView: View {
    @Binding var stars: Int
    @ScaledMetric private var scaledSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(stars: Binding<Int>, size: CGFloat = 28) {
        _stars = stars
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .title)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    stars = stars == value ? 0 : value
                } label: {
                    Image(systemName: value <= stars ? "star.fill" : "star")
                        .font(.system(size: scaledSize))
                        .foregroundStyle(value <= stars ? AnyShapeStyle(Color.star) : AnyShapeStyle(.tertiary))
                        .symbolEffect(.bounce, value: reduceMotion ? 0 : (value <= stars ? stars : 0))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(trigger: stars) { _, new in new == 5 ? .success : .selection }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your stars")
        .accessibilityValue(stars == 0 ? "Not rated" : starsDescription(Double(stars)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: stars = min(5, stars + 1)
            case .decrement: stars = max(0, stars - 1)
            @unknown default: break
            }
        }
    }
}

/// Read-only stars for cards and lists.
struct StarsLabel: View {
    let stars: Double
    @ScaledMetric private var scaledSize: CGFloat

    init(stars: Double, size: CGFloat = 12) {
        self.stars = stars
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .subheadline)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: symbol(for: value))
                    .font(.system(size: scaledSize))
                    .foregroundStyle(Double(value) - 0.5 <= stars ? Color.star : Color.secondary.opacity(0.4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(starsDescription(stars))
    }

    private func symbol(for value: Int) -> String {
        if Double(value) <= stars { return "star.fill" }
        if Double(value) - 0.5 <= stars { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// Stars marked as yours, so nobody mistakes them for a family score.
struct YourStarsLabel: View {
    let stars: Double
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 4) {
            Text("You")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            StarsLabel(stars: stars, size: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your rating, \(starsDescription(stars))")
    }
}

/// Shows the holiday when there is one, otherwise the season.
struct OccasionBadge: View {
    let meal: Meal

    var body: some View {
        if let holiday = meal.holiday {
            Text(holiday.label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.thinMaterial, in: Capsule())
                .accessibilityLabel(holiday.name)
        } else {
            SeasonBadge(season: meal.season)
        }
    }
}

/// "★ 4.8 · you" — one quiet label instead of a row of five stars, for lists
/// where nearly everything is highly rated.
struct CompactStars: View {
    let stars: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .foregroundStyle(Color.star)
            let rounded = (stars * 10).rounded() / 10
            Text(rounded.formatted(.number.precision(.fractionLength(rounded == rounded.rounded() ? 0 : 1))))
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your rating, \(starsDescription(stars))")
    }
}

struct SeasonBadge: View {
    let season: Season

    var body: some View {
        Text("\(season.emoji) \(season.displayName)")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel(season.displayName)
    }
}

/// Decodes thumbnails off the main thread and caches them so the feed scrolls smoothly.
struct PhotoThumbnail: View {
    @ObservedObject private var photo: Photo
    private let hasPhoto: Bool
    private let useFullImage: Bool

    @State private var image: UIImage?

    init(photo: Photo?, useFullImage: Bool = false) {
        // Placeholder object for the "no photo" state keeps @ObservedObject non-optional.
        _photo = ObservedObject(wrappedValue: photo ?? PhotoThumbnail.placeholder)
        self.hasPhoto = photo != nil
        self.useFullImage = useFullImage
    }

    private static let placeholder = Photo(entity: SundayModel.shared.entitiesByName["Photo"]!, insertInto: nil)

    private var taskKey: String {
        guard hasPhoto else { return "none" }
        // Changes when the image data arrives from iCloud, so we retry. Only
        // touch the full image when it's the one we show (it's ~10x larger).
        let size = useFullImage ? (photo.imageData?.count ?? 0) : (photo.thumbnailData?.count ?? 0)
        return "\(photo.objectID)-\(size)"
    }

    var body: some View {
        // Color.clear takes exactly the size it's offered, so a scaled-to-fill
        // photo can never push the layout around or spill past the frame.
        Color.secondary.opacity(0.12)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if !hasPhoto {
                    Image(systemName: "fork.knife")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .clipped()
        .task(id: taskKey) {
            image = hasPhoto ? await PhotoCache.image(for: photo, full: useFullImage) : nil
        }
    }
}

@MainActor
enum PhotoCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for photo: Photo, full: Bool) async -> UIImage? {
        guard let data = full ? (photo.imageData ?? photo.thumbnailData) : (photo.thumbnailData ?? photo.imageData) else { return nil }
        let key = "\(photo.objectID.uriRepresentation().absoluteString)-\(full)-\(data.count)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let image = UIImage(data: data) else { return nil }
            return await image.byPreparingForDisplay() ?? image
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

extension Date {
    var dinnerFormatted: String {
        formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }
}

// MARK: Keepsake type & people

extension View {
    /// Serif (New York) for the things a family would put in an album:
    /// dish names, big titles, the dinners-together number.
    func keepsake() -> some View { fontDesign(.serif) }
}

/// A person as an initial on a warm tinted circle. The tint is derived from
/// the name, so "Mom" is always the same color on every device.
struct CookAvatar: View {
    let name: String
    var size: CGFloat = 22

    private static let tints: [Color] = [
        Color(red: 0.84, green: 0.45, blue: 0.27), Color(red: 0.36, green: 0.55, blue: 0.42),
        Color(red: 0.38, green: 0.47, blue: 0.70), Color(red: 0.66, green: 0.42, blue: 0.62),
        Color(red: 0.75, green: 0.58, blue: 0.22), Color(red: 0.31, green: 0.58, blue: 0.62),
    ]

    private var tint: Color {
        let sum = name.lowercased().unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Self.tints[abs(sum) % Self.tints.count]
    }

    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint, in: Circle())
            .accessibilityHidden(true)
    }
}

/// "[M] Mom" — avatar plus name.
struct CookLabel: View {
    let name: String
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: 6) {
            CookAvatar(name: name, size: size)
            Text(name)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cooked by \(name)")
    }
}

/// Small "Rate" capsule for dinners you haven't rated yet.
struct RatePrompt: View {
    var body: some View {
        Label("Rate", systemImage: "star")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.sundayAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(Color.sundayAccent.opacity(0.5), lineWidth: 1))
            .accessibilityLabel("Not rated yet")
    }
}
