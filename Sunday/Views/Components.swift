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
}

/// Tap a star to set it; tap the same star again to clear.
struct StarRatingView: View {
    @Binding var stars: Int
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    stars = stars == value ? 0 : value
                } label: {
                    Image(systemName: value <= stars ? "star.fill" : "star")
                        .font(.system(size: size))
                        .foregroundStyle(value <= stars ? Color.yellow : Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
            }
        }
        .sensoryFeedback(.selection, trigger: stars)
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(stars) of 5")
    }
}

/// Read-only stars for cards and lists.
struct StarsLabel: View {
    let stars: Double
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: symbol(for: value))
                    .font(.system(size: size))
                    .foregroundStyle(Double(value) - 0.5 <= stars ? Color.yellow : Color.secondary.opacity(0.4))
            }
        }
        .accessibilityLabel(String(format: "%.1f stars", stars))
    }

    private func symbol(for value: Int) -> String {
        if Double(value) <= stars { return "star.fill" }
        if Double(value) - 0.5 <= stars { return "star.leadinghalf.filled" }
        return "star"
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
    }
}

/// Decodes thumbnails off the main thread and caches them so the feed scrolls smoothly.
struct PhotoThumbnail: View {
    let photo: Photo?
    var useFullImage = false

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.12))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if photo == nil {
                Image(systemName: "fork.knife")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: photo?.objectID) {
            image = await PhotoCache.image(for: photo, full: useFullImage)
        }
    }
}

@MainActor
enum PhotoCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for photo: Photo?, full: Bool) async -> UIImage? {
        guard let photo else { return nil }
        let key = "\(photo.objectID.uriRepresentation().absoluteString)-\(full)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = full ? (photo.imageData ?? photo.thumbnailData) : (photo.thumbnailData ?? photo.imageData) else { return nil }
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
