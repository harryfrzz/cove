import Foundation
import SwiftData
import UIKit

/// Background ingestion pipeline. Owns its own SwiftData context via
/// `@ModelActor`, so all model reads/writes happen on this actor and only
/// value snapshots cross to the main actor (Live Activity, UI).
///
/// Order per item: decode image → OCR → classify/extract/summarize →
/// embed image → embed enriched text → `.ready`. Progress is persisted after
/// every step, so a kill mid-item loses at most one step, and a failed
/// summarization still leaves OCR text and embeddings searchable.
///
/// The queue is deliberately serial (one item in flight): several Core ML /
/// language-model invocations running concurrently on a phone cause memory
/// spikes and thermal throttling, not speedups.
@ModelActor
actor ShelfProcessor {
    static let shared = ShelfProcessor(modelContainer: CoveStore.shared)

    private var queue: [UUID] = []
    private var isDraining = false

    // MARK: - Public API

    /// Queue an item for background processing and return immediately.
    func enqueue(itemID: UUID) {
        guard !queue.contains(itemID) else { return }
        queue.append(itemID)
        drainSoon()
    }

    /// Process one item to completion and report its final state. Used by the
    /// screenshot App Intent, which must answer with a dialog.
    func processNow(itemID: UUID) async -> ShelfProcessingState {
        await process(itemID: itemID)
        return fetchItem(itemID)?.processingState ?? .failed
    }

    /// Reset an item that ended `.failed` and run it again.
    func retry(itemID: UUID) {
        guard let item = fetchItem(itemID) else { return }
        item.processingState = .queued
        item.failureMessage = nil
        saveQuietly()
        enqueue(itemID: itemID)
    }

    /// Startup reconciliation: anything left `.processing` by a kill goes back
    /// to `.queued` and is re-run; `.ready` items embedded with an older model
    /// version are re-embedded so vectors stay comparable.
    func reconcileAtLaunch() {
        let stuck = (try? modelContext.fetch(FetchDescriptor<ShelfItem>()))?.filter {
            $0.processingState == .processing || $0.processingState == .queued
        } ?? []
        for item in stuck {
            item.processingState = .queued
            queue.append(item.id)
        }
        saveQuietly()

        let currentVersion = AIServices.currentEmbeddingModelVersion
        let stale = (try? modelContext.fetch(FetchDescriptor<ShelfItem>()))?.filter {
            $0.processingState == .ready
                && $0.embeddingModelVersion != currentVersion
        } ?? []
        for item in stale {
            reembedQueue.append(item.id)
        }

        drainSoon()
    }

    // MARK: - Queue

    private var reembedQueue: [UUID] = []

    private func drainSoon() {
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    private func drain() async {
        while let next = queue.first {
            queue.removeFirst()
            await process(itemID: next)
        }
        while let next = reembedQueue.first {
            reembedQueue.removeFirst()
            await reembed(itemID: next)
        }
        isDraining = false
    }

    // MARK: - Processing

    private func process(itemID: UUID) async {
        guard let item = fetchItem(itemID) else { return }
        guard item.processingState == .queued || item.processingState == .processing else {
            return
        }

        let snapshot = item.activitySnapshot
        item.processingState = .processing
        item.failureMessage = nil
        saveQuietly()
        await ProcessingLiveActivityManager.shared.itemStarted(snapshot)

        let services = AIServices.current
        var hardFailure: String?

        // 1. Decode once; OCR and embedding share the image.
        var decodedImage: UIImage?
        if let imageData = item.imageData {
            decodedImage = UIImage(data: imageData)
            if decodedImage == nil {
                hardFailure = "The saved image data could not be decoded."
            }
        }

        // 2. OCR (images only). Empty text is a normal outcome.
        if let image = decodedImage {
            await ProcessingLiveActivityManager.shared.itemProgress(
                id: snapshot.id, phase: .recognizingText, progress: 0.3
            )
            do {
                let text = try await services.ocr.recognizeText(in: image)
                item.extractedText = text.isEmpty ? nil : text
                saveQuietly()
            } catch {
                hardFailure = "Text recognition failed: \(error.localizedDescription)"
            }
        }

        // 3. Classify + structured extraction + summary. Unavailable language
        // model degrades gracefully: the item stays searchable without it.
        await ProcessingLiveActivityManager.shared.itemProgress(
            id: snapshot.id, phase: .summarizing, progress: 0.55
        )
        let sourceText = enrichmentSource(for: item)
        if !sourceText.isEmpty {
            do {
                let enrichment = try await services.extraction.enrich(
                    text: sourceText,
                    kind: item.kind
                )
                item.summary = enrichment.summary
                item.tags = enrichment.tags
                item.extraction = enrichment.extraction
                saveQuietly()
            } catch {
                item.summary = nil
                item.extraction = nil
                if item.tags.isEmpty {
                    item.tags = [item.kind.label.lowercased()]
                }
                saveQuietly()
            }
        }

        // 4. Embeddings: the image itself, then the enriched text. Failure is
        // not fatal — keyword search still works.
        await ProcessingLiveActivityManager.shared.itemProgress(
            id: snapshot.id, phase: .makingSearchable, progress: 0.8
        )
        do {
            if let image = decodedImage {
                let vector = try await services.embeddings.embed(image: image)
                item.embedding = vector
                item.embeddingDimension = vector.count
                item.embeddingModelVersion = AIServices.currentEmbeddingModelVersion
                saveQuietly()
            }
            let enrichedText = item.searchableText
            if !enrichedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let vector = try await services.embeddings.embed(text: enrichedText)
                item.textEmbedding = vector
                item.embeddingDimension = vector.count
                item.embeddingModelVersion = AIServices.currentEmbeddingModelVersion
                saveQuietly()
            }
        } catch {
            // Persisted state so far (OCR text, summary) remains searchable.
        }

        // 5. Terminal state. Only an unusable image is a hard failure; any
        // partial result is kept and shown.
        if let hardFailure, item.extractedText == nil, item.embedding == nil {
            item.processingState = .failed
            item.failureMessage = hardFailure
            saveQuietly()
            await ProcessingLiveActivityManager.shared.itemFailed(snapshot)
        } else {
            item.processingState = .ready
            item.failureMessage = nil
            saveQuietly()
            await ProcessingLiveActivityManager.shared.itemFinished(snapshot)
        }
    }

    /// Refresh embeddings only (model-version migration), without redoing OCR
    /// or summarization.
    private func reembed(itemID: UUID) async {
        guard let item = fetchItem(itemID) else { return }
        let services = AIServices.current
        do {
            if let imageData = item.imageData, let image = UIImage(data: imageData) {
                let vector = try await services.embeddings.embed(image: image)
                item.embedding = vector
                item.embeddingDimension = vector.count
            }
            let enrichedText = item.searchableText
            if !enrichedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let vector = try await services.embeddings.embed(text: enrichedText)
                item.textEmbedding = vector
                item.embeddingDimension = vector.count
            }
            item.embeddingModelVersion = AIServices.currentEmbeddingModelVersion
            saveQuietly()
        } catch {
            // Stale vectors stay flagged by their version and are skipped in
            // search; the next launch retries.
        }
    }

    private func enrichmentSource(for item: ShelfItem) -> String {
        switch item.kind {
        case .screenshot, .image:
            [item.title, item.userNote, item.extractedText]
                .compactMap { $0 }
                .joined(separator: "\n")
        case .link:
            [item.title, item.userNote, item.linkTitle, item.linkHost, item.linkURL?.absoluteString]
                .compactMap { $0 }
                .joined(separator: "\n")
        case .text:
            [item.title, item.userNote]
                .compactMap { $0 }
                .joined(separator: "\n")
        }
    }

    private func fetchItem(_ id: UUID) -> ShelfItem? {
        var descriptor = FetchDescriptor<ShelfItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func saveQuietly() {
        do {
            try modelContext.save()
        } catch {
            // A failed checkpoint save leaves the previous checkpoint intact;
            // the launch reconciliation pass re-runs anything incomplete.
        }
    }
}
