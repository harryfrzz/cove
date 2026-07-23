import ImageIO
import SwiftUI
import UIKit

/// Decodes and caches small bitmaps for grid cells so the stored
/// full-resolution copies never hit the render pipeline directly.
/// Downsampling happens through ImageIO off the main thread, producing a
/// bitmap at the exact pixel size a cell needs — crisp minification without
/// holding megapixel images in memory per cell.
enum ThumbnailStore {
    private static let thumbnails: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
    private static let aspects = NSCache<NSString, NSNumber>()

    /// Height/width ratio of the stored image, read from the file header
    /// without decoding pixels. Cached per item so repeated layout passes
    /// are dictionary lookups.
    static func aspectRatio(id: UUID, data: Data?, fallback: CGFloat) -> CGFloat {
        let key = id.uuidString as NSString
        if let cached = aspects.object(forKey: key) {
            return CGFloat(truncating: cached)
        }
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0
        else {
            return fallback
        }
        // EXIF orientations 5-8 swap the axes.
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let ratio = orientation >= 5 ? width / height : height / width
        aspects.setObject(NSNumber(value: Double(ratio)), forKey: key)
        return ratio
    }

    /// Bitmap sized to fill `pixelSize` (scale-to-fill, so the shorter
    /// coverage axis matches exactly and the other overflows for cropping).
    /// Never upscales beyond the stored image.
    static func thumbnail(id: UUID, data: Data?, filling pixelSize: CGSize) async -> UIImage? {
        let key = "\(id.uuidString)-\(Int(pixelSize.width))x\(Int(pixelSize.height))" as NSString
        if let cached = thumbnails.object(forKey: key) {
            return cached
        }
        guard let data else { return nil }

        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
                  let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
                  width > 0, height > 0
            else {
                return nil
            }

            let fillScale = max(pixelSize.width / width, pixelSize.height / height)
            let longestSide = min(max(width, height) * fillScale, max(width, height))
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: ceil(longestSide)
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }.value

        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale) * 4
            thumbnails.setObject(image, forKey: key, cost: cost)
        }
        return image
    }
}

/// Async-loading thumbnail for grid and list cells: shows a soft placeholder,
/// then the downsampled bitmap cropped to fill its frame.
struct ShelfThumbnail: View {
    let item: ShelfItem
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var size: CGSize = .zero

    var body: some View {
        // Color.clear adopts exactly the size the parent proposes, and the
        // image lives in an overlay so its bitmap dimensions can never
        // inflate the layout — only spill visually, which .clipped() crops.
        // Screenshots anchor to their top edge when cropped — that's where
        // the content starts; photos keep the usual center crop.
        Color.clear
            .overlay(alignment: item.kind == .screenshot ? .top : .center) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    CoveTheme.ink.opacity(0.06)
                }
            }
            .clipped()
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            size = newSize
        }
        .task(id: "\(item.id.uuidString)-\(Int(size.width))x\(Int(size.height))") {
            guard size.width > 0, size.height > 0 else { return }
            image = await ThumbnailStore.thumbnail(
                id: item.id,
                data: item.imageData,
                filling: CGSize(
                    width: size.width * displayScale,
                    height: size.height * displayScale
                )
            )
        }
    }
}
