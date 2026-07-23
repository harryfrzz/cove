import Foundation
import FoundationModels

// MARK: - Structured extraction contract

/// What the enrichment step of the pipeline produces. Persisted on
/// `ShelfItem` (extraction as JSON) so the UI can surface typed fields.
struct ItemEnrichment: Sendable {
    var summary: String
    var tags: [String]
    var extraction: ItemExtraction?
}

/// Flat, storage-facing extraction record (Codable for `extractionJSON`).
struct ItemExtraction: Codable, Sendable, Equatable {
    var category: String

    // Receipt
    var merchant: String?
    var total: String?
    var currency: String?
    var date: String?
    var expenseCategory: String?

    // Event
    var eventTitle: String?
    var eventStart: String?
    var eventEnd: String?
    var eventLocation: String?

    // Link / note
    var shortTitle: String?
}

protocol StructuredExtractionService: Sendable {
    /// Classifies the text, runs the matching extraction schema, and returns
    /// a summary plus typed fields. Throws when the system model is
    /// unavailable — callers must degrade, not fail the item.
    func enrich(text: String, kind: ShelfItemKind) async throws -> ItemEnrichment
}

// MARK: - Generable schemas (guided generation, no string parsing)

@Generable(description: "Classification of a captured item")
private struct ContentClassification {
    @Guide(description: "The content type", .anyOf(["receipt", "event", "article", "note"]))
    var category: String
}

@Generable(description: "Fields extracted from a purchase receipt")
private struct ReceiptExtraction {
    @Guide(description: "Merchant or store name")
    var merchant: String
    @Guide(description: "Final total amount as printed, digits only, e.g. 22.50")
    var total: String
    @Guide(description: "Currency symbol or code as printed, e.g. $ or USD or ₹")
    var currency: String
    @Guide(description: "Purchase date as printed, or empty if absent")
    var date: String
    @Guide(description: "One-word spending category such as groceries, dining, transport")
    var category: String
    @Guide(description: "One-line summary of the purchase")
    var summary: String
    @Guide(description: "Search tags", .count(3...5))
    var tags: [String]
}

@Generable(description: "Fields extracted from an event, ticket, or invitation")
private struct EventExtraction {
    @Guide(description: "Event title")
    var title: String
    @Guide(description: "Start date and time as written in the text")
    var startDate: String
    @Guide(description: "End date and time, or empty if absent")
    var endDate: String
    @Guide(description: "Venue or location, or empty if absent")
    var location: String
    @Guide(description: "One-line summary of the event")
    var summary: String
    @Guide(description: "Search tags", .count(3...5))
    var tags: [String]
}

@Generable(description: "Summary of a saved link, article, or note")
private struct NoteExtraction {
    @Guide(description: "Short title, at most eight words")
    var shortTitle: String
    @Guide(description: "One-line summary")
    var summary: String
    @Guide(description: "Search tags", .count(3...5))
    var tags: [String]
}

// MARK: - Service

/// On-device summarization and structured extraction using Apple's
/// Foundation Models framework. Availability is re-checked on every call:
/// Apple Intelligence can be toggled or the model evicted while the app runs.
struct FoundationModelsService: SummarizationService, StructuredExtractionService {
    enum ModelUnavailable: LocalizedError {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case other

        var errorDescription: String? {
            switch self {
            case .deviceNotEligible:
                "This device does not support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                "Apple Intelligence is turned off in Settings."
            case .modelNotReady:
                "The on-device language model is still downloading."
            case .other:
                "The on-device language model is unavailable."
            }
        }
    }

    /// Head+tail truncation budget in characters. The system model's context
    /// window is small (~4k tokens shared with instructions and schema);
    /// receipts and articles carry their signal at the start and end.
    private static let headBudget = 2400
    private static let tailBudget = 800

    static func availabilityError() -> ModelUnavailable? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .other
        }
    }

    // MARK: SummarizationService

    func summarize(_ text: String) async throws -> String {
        if let unavailable = Self.availabilityError() { throw unavailable }

        let session = LanguageModelSession(
            instructions: "You summarize a saved personal item in one short sentence. Reply with only that sentence."
        )
        let response = try await session.respond(to: Self.truncated(text))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: StructuredExtractionService

    func enrich(text: String, kind: ShelfItemKind) async throws -> ItemEnrichment {
        if let unavailable = Self.availabilityError() { throw unavailable }

        let content = Self.truncated(text)
        let category = try await classify(content, kind: kind)

        switch category {
        case "receipt":
            let session = LanguageModelSession(
                instructions: "Extract receipt fields exactly as they appear in the text. Do not invent values."
            )
            let receipt = try await session.respond(
                to: content,
                generating: ReceiptExtraction.self
            ).content
            return ItemEnrichment(
                summary: receipt.summary,
                tags: receipt.tags,
                extraction: ItemExtraction(
                    category: "receipt",
                    merchant: receipt.merchant,
                    total: receipt.total,
                    currency: receipt.currency,
                    date: receipt.date.isEmpty ? nil : receipt.date,
                    expenseCategory: receipt.category
                )
            )

        case "event":
            let session = LanguageModelSession(
                instructions: "Extract event details exactly as they appear in the text. Do not invent values."
            )
            let event = try await session.respond(
                to: content,
                generating: EventExtraction.self
            ).content
            return ItemEnrichment(
                summary: event.summary,
                tags: event.tags,
                extraction: ItemExtraction(
                    category: "event",
                    eventTitle: event.title,
                    eventStart: event.startDate,
                    eventEnd: event.endDate.isEmpty ? nil : event.endDate,
                    eventLocation: event.location.isEmpty ? nil : event.location
                )
            )

        default:
            let session = LanguageModelSession(
                instructions: "You title, summarize, and tag a saved personal item."
            )
            let note = try await session.respond(
                to: content,
                generating: NoteExtraction.self
            ).content
            return ItemEnrichment(
                summary: note.summary,
                tags: note.tags,
                extraction: ItemExtraction(
                    category: category == "article" ? "link" : "note",
                    shortTitle: note.shortTitle
                )
            )
        }
    }

    private func classify(_ content: String, kind: ShelfItemKind) async throws -> String {
        // Links are links; only free text and OCR output need routing.
        if kind == .link { return "article" }

        let session = LanguageModelSession(
            instructions: "Classify the text of a saved item. A receipt shows purchased items or amounts paid. An event has a date and a happening to attend. An article is saved web content. Everything else is a note."
        )
        let result = try await session.respond(
            to: content,
            generating: ContentClassification.self
        )
        return result.content.category
    }

    /// Head+tail truncation: keeps the opening (merchant, title, headers) and
    /// the closing lines (totals, signatures) of long text.
    static func truncated(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > headBudget + tailBudget else { return trimmed }
        let head = trimmed.prefix(headBudget)
        let tail = trimmed.suffix(tailBudget)
        return "\(head)\n…\n\(tail)"
    }
}

// MARK: - Extraction storage helpers

extension ShelfItem {
    var extraction: ItemExtraction? {
        get {
            guard let extractionJSON, let data = extractionJSON.data(using: .utf8) else {
                return nil
            }
            return try? JSONDecoder().decode(ItemExtraction.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                extractionJSON = nil
                return
            }
            extractionJSON = String(decoding: data, as: UTF8.self)
        }
    }
}
