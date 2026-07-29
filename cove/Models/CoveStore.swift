import SwiftData

enum CoveStore {
    // ModelContainer is Sendable; both the main actor and the background
    // ShelfProcessor actor derive their own contexts from this container.
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: ShelfItem.self, ChatThread.self)
        } catch {
            fatalError("Could not create Cove’s local SwiftData store: \(error)")
        }
    }()
}
