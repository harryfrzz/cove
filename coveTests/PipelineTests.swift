import Foundation
import SwiftData
import Testing
import UIKit
@testable import cove

/// State-transition tests for the background pipeline, run against an
/// in-memory store with the mock AI services (forced via UserDefaults).
/// Serialized: the mock flag is process-global.
@Suite(.serialized) struct PipelineTests {
    private func withMockServices<T>(_ body: (ModelContainer, ShelfProcessor) async throws -> T) async throws -> T {
        UserDefaults.standard.set(true, forKey: AIServiceMode.mockDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: AIServiceMode.mockDefaultsKey) }

        let container = try ModelContainer(
            for: ShelfItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let processor = ShelfProcessor(modelContainer: container)
        return try await body(container, processor)
    }

    @MainActor
    private func fetch(_ id: UUID, from container: ModelContainer) throws -> ShelfItem? {
        var descriptor = FetchDescriptor<ShelfItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try container.mainContext.fetch(descriptor).first
    }

    @Test func noteGoesQueuedToReadyWithEnrichment() async throws {
        try await withMockServices { container, processor in
            let item = ShelfItem(
                kind: .text,
                title: "Kyoto coffee list",
                userNote: "Try Weekenders Coffee near Kawaramachi.",
                processingState: .queued
            )
            await MainActor.run { container.mainContext.insert(item) }
            try await MainActor.run { try container.mainContext.save() }

            let finalState = await processor.processNow(itemID: item.id)
            #expect(finalState == .ready)

            let processed = try await fetch(item.id, from: container)
            #expect(processed?.summary?.isEmpty == false)
            #expect(processed?.tags.isEmpty == false)
            #expect(processed?.textEmbedding?.count == 64)
            #expect(processed?.embeddingModelVersion == "mock-64")
        }
    }

    @Test func screenshotGetsOCRTextAndBothEmbeddings() async throws {
        try await withMockServices { container, processor in
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
            let image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            }
            let item = ShelfItem(
                kind: .screenshot,
                title: "Saved screenshot",
                imageData: image.pngData(),
                processingState: .queued
            )
            await MainActor.run { container.mainContext.insert(item) }
            try await MainActor.run { try container.mainContext.save() }

            let finalState = await processor.processNow(itemID: item.id)
            #expect(finalState == .ready)

            let processed = try await fetch(item.id, from: container)
            #expect(processed?.extractedText?.contains("NORTH STAR MARKET") == true)
            #expect(processed?.embedding != nil)
            #expect(processed?.textEmbedding != nil)
            #expect(processed?.extraction?.category == "receipt")
        }
    }

    @Test func undecodableImageFailsWithRetryableError() async throws {
        try await withMockServices { container, processor in
            let item = ShelfItem(
                kind: .screenshot,
                title: "Broken",
                imageData: Data([0xDE, 0xAD, 0xBE, 0xEF]),
                processingState: .queued
            )
            await MainActor.run { container.mainContext.insert(item) }
            try await MainActor.run { try container.mainContext.save() }

            let finalState = await processor.processNow(itemID: item.id)
            #expect(finalState == .failed)

            let failed = try await fetch(item.id, from: container)
            #expect(failed?.failureMessage?.isEmpty == false)

            // Retry re-queues and re-runs (still failing, but through the
            // full state machine rather than staying stuck).
            await processor.retry(itemID: item.id)
            // Drain: retry enqueues asynchronously; wait for it to settle.
            for _ in 0..<50 {
                try await Task.sleep(for: .milliseconds(100))
                let state = try await fetch(item.id, from: container)?.processingState
                if state == .failed { break }
            }
            let after = try await fetch(item.id, from: container)?.processingState
            #expect(after == .failed)
        }
    }

    @Test func reconciliationRequeuesStuckItems() async throws {
        try await withMockServices { container, processor in
            let stuck = ShelfItem(
                kind: .text,
                title: "Stranded by a kill",
                userNote: "note body",
                processingState: .processing
            )
            await MainActor.run { container.mainContext.insert(stuck) }
            try await MainActor.run { try container.mainContext.save() }

            await processor.reconcileAtLaunch()

            var state: ShelfProcessingState?
            for _ in 0..<100 {
                try await Task.sleep(for: .milliseconds(100))
                state = try await fetch(stuck.id, from: container)?.processingState
                if state == .ready { break }
            }
            #expect(state == .ready)
        }
    }
}
