import UIKit

enum ImageProcessing {
    struct Prepared: Sendable {
        let full: Data
        let thumbnail: Data
    }

    /// Downsizes a photo for iCloud: ~2048px full image, ~600px thumbnail for the feed.
    static func prepare(_ image: UIImage) -> Prepared? {
        guard let full = resized(image, maxDimension: 2048).jpegData(compressionQuality: 0.8),
              let thumbnail = resized(image, maxDimension: 600).jpegData(compressionQuality: 0.7)
        else { return nil }
        return Prepared(full: full, thumbnail: thumbnail)
    }

    static func prepareAsync(_ image: UIImage) async -> Prepared? {
        await Task.detached(priority: .userInitiated) { prepare(image) }.value
    }

    private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return normalized(image) }
        let scale = maxDimension / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Bakes in orientation so JPEGs display upright everywhere.
    private static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
