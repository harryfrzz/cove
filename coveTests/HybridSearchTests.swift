import Foundation
import SwiftData
import Testing
import UIKit
@testable import cove

/// Ranking behavior on a fixed fixture set, with a stub embedding service so
/// results are deterministic and Core ML free.
@MainActor
@Suite struct HybridSearchTests {
    private struct StubEmbeddings: EmbeddingService {
        let queryVector: [Float]

        func embed(image: UIImage) async throws -> [Float] { queryVector }
        func embed(text: String) async throws -> [Float] { queryVector }
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: ShelfItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func keywordHitOutranksUnrelatedItems() async throws {
        let context = try makeContext()
        let receipt = ShelfItem(
            kind: .screenshot,
            title: "Saved screenshot",
            extractedText: "NORTH STAR MARKET\nTotal $22.50",
            processingState: .ready
        )
        let cat = ShelfItem(kind: .text, title: "Cat photo ideas", processingState: .ready)
        context.insert(receipt)
        context.insert(cat)

        let search = HybridSearchService(embeddings: StubEmbeddings(queryVector: [1, 0, 0]))
        let results = try await search.search("north star market", in: [cat, receipt])

        #expect(results.first?.id == receipt.id)
    }

    @Test func semanticSimilarityRanksWithoutKeywordOverlap() async throws {
        let context = try makeContext()
        // Query vector [1,0,0]: itemA aligned, itemB orthogonal.
        let itemA = ShelfItem(kind: .text, title: "alpha", processingState: .ready)
        itemA.embedding = [1, 0, 0]
        let itemB = ShelfItem(kind: .text, title: "beta", processingState: .ready)
        itemB.embedding = [0, 1, 0]
        context.insert(itemA)
        context.insert(itemB)

        let search = HybridSearchService(embeddings: StubEmbeddings(queryVector: [1, 0, 0]))
        let results = try await search.search("unrelated words", in: [itemB, itemA])

        #expect(results.first?.id == itemA.id)
        // itemB: no keyword hit, cosine 0 < floor — must be dropped entirely.
        #expect(!results.contains { $0.id == itemB.id })
    }

    @Test func emptyQueryReturnsEverything() async throws {
        let context = try makeContext()
        let item = ShelfItem(kind: .text, title: "anything", processingState: .ready)
        context.insert(item)

        let search = HybridSearchService(embeddings: StubEmbeddings(queryVector: [1, 0, 0]))
        let results = try await search.search("   ", in: [item])
        #expect(results.count == 1)
    }

    @Test func mismatchedDimensionsAreSkippedNotCompared() async throws {
        let context = try makeContext()
        // Stale 64-dim mock vector must not be dotted against a 3-dim query.
        let stale = ShelfItem(kind: .text, title: "coffee notes", processingState: .ready)
        stale.embedding = [Float](repeating: 0.125, count: 64)
        context.insert(stale)

        let search = HybridSearchService(embeddings: StubEmbeddings(queryVector: [1, 0, 0]))
        // Keyword still matches, so the item survives via the keyword list.
        let results = try await search.search("coffee", in: [stale])
        #expect(results.first?.id == stale.id)
    }
}
