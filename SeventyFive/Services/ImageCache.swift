import SwiftUI
import UIKit
import ImageIO

/// Decodes stored photos at the size they're displayed, off the main thread, and keeps them.
///
/// Before this, every redraw decoded a full-size JPEG on the main thread — the photo grid,
/// the camera's ghost overlay while its slider moved, and both halves of the compare view on
/// every frame of a drag. ImageIO's thumbnail path decodes straight to the target size, so a
/// grid cell costs ~300 px of memory instead of 12 MP.
final class ImageCache {
    static let shared = ImageCache()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 120 * 1024 * 1024
        return cache
    }()

    private func key(_ fileName: String, _ maxPixelSize: CGFloat) -> NSString {
        "\(fileName)#\(Int(maxPixelSize))" as NSString
    }

    func cached(fileName: String, maxPixelSize: CGFloat) -> UIImage? {
        cache.object(forKey: key(fileName, maxPixelSize))
    }

    /// Synchronous decode. Prefer `load` from views; this exists for one-off work such as
    /// rendering a share image.
    func image(fileName: String, maxPixelSize: CGFloat) -> UIImage? {
        if let hit = cached(fileName: fileName, maxPixelSize: maxPixelSize) { return hit }
        guard let url = PhotoStorageService.url(for: fileName),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key(fileName, maxPixelSize), cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    func load(fileName: String, maxPixelSize: CGFloat) async -> UIImage? {
        if let hit = cached(fileName: fileName, maxPixelSize: maxPixelSize) { return hit }
        return await Task.detached(priority: .userInitiated) {
            ImageCache.shared.image(fileName: fileName, maxPixelSize: maxPixelSize)
        }.value
    }

    func evict(fileName: String) {
        for size in PhotoSize.allCases {
            cache.removeObject(forKey: key(fileName, size.pixels))
        }
    }

    func removeAll() { cache.removeAllObjects() }
}

/// The handful of sizes photos are decoded at, so cache keys are shared between screens.
enum PhotoSize: CaseIterable {
    case thumbnail, overlay, full

    var pixels: CGFloat {
        switch self {
        case .thumbnail: return 360
        case .overlay: return 1400
        case .full: return 2400
        }
    }
}

/// Shows a stored progress photo, decoded asynchronously at the requested size.
struct StoredPhotoView: View {
    let fileName: String
    var size: PhotoSize = .thumbnail
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Theme.surface2)
            }
        }
        .task(id: fileName) {
            if let hit = ImageCache.shared.cached(fileName: fileName, maxPixelSize: size.pixels) {
                image = hit
            } else {
                image = await ImageCache.shared.load(fileName: fileName, maxPixelSize: size.pixels)
            }
        }
    }
}
