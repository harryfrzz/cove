import Foundation
import UIKit

struct MockAIServices: EmbeddingService, OCRService, SummarizationService,
    ImageUnderstandingService, SearchService, StructuredExtractionService, Sendable {
    private let embeddingDimension = 64

    func enrich(text: String, kind: ShelfItemKind) async throws -> ItemEnrichment {
        try await pause(milliseconds: 500)
        let summary = try await summarize(text)
        switch kind {
        case .screenshot, .image:
            return ItemEnrichment(
                summary: summary,
                tags: ["screenshot", "receipt", "reference"],
                extraction: ItemExtraction(
                    category: "receipt",
                    merchant: "North Star Market",
                    total: "22.50",
                    currency: "$",
                    date: "22 July 2026",
                    expenseCategory: "groceries"
                )
            )
        case .link:
            return ItemEnrichment(
                summary: summary,
                tags: ["link", "web", "read-later"],
                extraction: ItemExtraction(category: "link", shortTitle: "Saved link")
            )
        case .text:
            return ItemEnrichment(
                summary: summary,
                tags: ["note", "idea", "personal"],
                extraction: ItemExtraction(category: "note", shortTitle: "Quick note")
            )
        }
    }

    func embed(image: UIImage) async throws -> [Float] {
        try await pause(milliseconds: 420)
        return randomNormalizedEmbedding()
    }

    func embed(text: String) async throws -> [Float] {
        try await pause(milliseconds: 320)
        return randomNormalizedEmbedding()
    }

    func recognizeText(in image: UIImage) async throws -> String {
        try await pause(milliseconds: 700)
        return """
        NORTH STAR MARKET
        Coffee beans              $18.00
        Oat milk                   $4.50
        Total                     $22.50
        Thank you — 22 July 2026
        """
    }

    func summarize(_ text: String) async throws -> String {
        try await pause(milliseconds: 540)
        let words = text
            .split(whereSeparator: \Character.isWhitespace)
            .prefix(12)
            .joined(separator: " ")
        guard !words.isEmpty else {
            return "A saved item ready to revisit later."
        }
        return "A quick reference about \(words), saved for easy recall."
    }

    func describe(image: UIImage) async throws -> String {
        try await pause(milliseconds: 620)
        return "A saved visual with prominent text and a clean, document-like layout."
    }

    func answer(question: String, about image: UIImage) async throws -> String {
        try await pause(milliseconds: 580)
        return "Mock answer: the key details are visible in the saved image and its extracted text."
    }

    func search(_ query: String, in items: [ShelfItem]) async throws -> [ShelfItem] {
        try await pause(milliseconds: 220)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return items }

        return items.filter {
            $0.searchableText.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private func pause(milliseconds: UInt64) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }

    private func randomNormalizedEmbedding() -> [Float] {
        let values = (0..<embeddingDimension).map { _ in Float.random(in: -1...1) }
        let magnitude = sqrt(values.reduce(0) { $0 + ($1 * $1) })
        guard magnitude > 0 else { return values }
        return values.map { $0 / magnitude }
    }
}
