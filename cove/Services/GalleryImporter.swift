import Observation
import Photos
import SwiftData
import UIKit

/// Indexes the photo library into the shelf: every image asset becomes a
/// `ShelfItem` (deduplicated by PHAsset identifier) carrying a downscaled
/// JPEG copy, then runs through the normal on-device pipeline (OCR → embed →
/// classify). iCloud-only originals are skipped — no network is ever used.
@MainActor
@Observable
final class GalleryImporter {
    static let shared = GalleryImporter()

    /// Newest-first cap per pass, so a huge library can't grind the phone for
    /// hours on first launch. Re-runs pick up where the cap cut off.
    private static let importLimit = 300
    /// Longest side of the stored copy; enough for OCR, embedding (256), and
    /// the masonry wall without duplicating full-resolution originals.
    private static let storedImageExtent: CGFloat = 1280

    private(set) var isImporting = false
    private(set) var importedCount = 0
    private(set) var totalCount = 0
    private(set) var isDenied = false

    private init() {}

    /// Requests read access (first call shows the system prompt) and imports
    /// anything not already on the shelf.
    func importLibrary() async {
        guard !isImporting else { return }

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            isDenied = status == .denied || status == .restricted
            return
        }
        isDenied = false

        isImporting = true
        defer {
            isImporting = false
            totalCount = 0
            importedCount = 0
        }

        let context = ModelContext(CoveStore.shared)
        var known = Set(
            ((try? context.fetch(FetchDescriptor<ShelfItem>())) ?? [])
                .compactMap(\.assetIdentifier)
        )

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)

        var pending: [PHAsset] = []
        assets.enumerateObjects { asset, _, stop in
            if !known.contains(asset.localIdentifier) {
                pending.append(asset)
            }
            if pending.count >= Self.importLimit {
                stop.pointee = true
            }
        }
        guard !pending.isEmpty else { return }

        totalCount = pending.count
        importedCount = 0

        for asset in pending {
            guard let jpegData = await Self.imageData(for: asset) else {
                importedCount += 1
                continue
            }

            let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
            let date = asset.creationDate ?? .now
            let item = ShelfItem(
                createdAt: date,
                kind: isScreenshot ? .screenshot : .image,
                title: "\(isScreenshot ? "Screenshot" : "Photo") · \(date.formatted(date: .abbreviated, time: .omitted))",
                imageData: jpegData,
                assetIdentifier: asset.localIdentifier,
                processingState: .queued
            )
            context.insert(item)
            try? context.save()
            known.insert(asset.localIdentifier)
            importedCount += 1

            await ShelfProcessor.shared.enqueue(itemID: item.id)
        }
    }

    /// Downscaled JPEG for one asset. Local only — iCloud originals that are
    /// not on device are skipped to keep the zero-network guarantee.
    private static func imageData(for asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false

        let target = CGSize(width: storedImageExtent, height: storedImageExtent)
        let image: UIImage? = await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                // The handler can fire twice (degraded then final); resume once.
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !isDegraded, !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
        return image?.jpegData(compressionQuality: 0.72)
    }
}
