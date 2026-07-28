import SwiftData

extension ModelContext {
    /// Removes items from the shelf permanently.
    ///
    /// There is deliberately nothing else to sweep up:
    ///
    /// - `ShelfItem.imageData` is `@Attribute(.externalStorage)`, so SwiftData
    ///   drops the backing file along with the model. No orphaned blobs.
    /// - `ThumbnailStore` is an in-memory `NSCache` that evicts under pressure
    ///   and never touches disk, so a deleted item's bitmap costs nothing and
    ///   can't be served to anything else — its keys are UUID-scoped.
    /// - Work already in flight inside `ShelfProcessor` is safe: every stage
    ///   re-fetches the item by id and returns when it has gone, so deleting
    ///   something mid-OCR cancels it rather than crashing.
    /// - The processing Live Activity re-synchronises from the item list, so a
    ///   deleted item drops out of it on the next pass.
    func deleteShelfItems(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        for item in items {
            delete(item)
        }
        try? save()
    }
}
