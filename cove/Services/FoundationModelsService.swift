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

    // Ticket
    var ticketType: String?
    var ticketTitle: String?
    var venueOrOperator: String?
    var ticketDateTime: String?
    var seatDetails: String?
    var referenceNumber: String?
    var price: String?
}

extension ItemExtraction {
    /// Whether the extracted fields actually back up the category.
    ///
    /// The classifier picks from a fixed list, so anything that is *none* of
    /// them still comes back wearing one of the labels — a certificate reads as
    /// an "event" because it has a name and a date, a poster reads as a
    /// "ticket". The label alone is therefore not evidence of anything. The
    /// pass-specific fields are: a seat, a booking reference, a total.
    ///
    /// Deliberately strict. A borderline item that gets excluded can still be
    /// added by hand from its detail page; a plain photo dressed as a boarding
    /// pass has no such escape.
    var describesAPass: Bool {
        switch category {
        // A receipt without an amount paid is not a receipt.
        case "receipt":
            Self.hasValue(total)
        // What makes a ticket is where you sit and what you booked under —
        // a certificate has a title and a date too, but never a seat.
        case "ticket":
            Self.hasValue(seatDetails)
                || Self.hasValue(referenceNumber)
                || Self.hasValue(price)
        // A date alone is the weakest possible signal; a venue alongside it is
        // what separates something you attend from something you were awarded.
        case "event":
            Self.hasValue(eventStart) && Self.hasValue(eventLocation)
        default:
            false
        }
    }

    private static func hasValue(_ field: String?) -> Bool {
        guard let field else { return false }
        return !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
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
    // "other" is the escape hatch. Without it the model had to force every
    // photograph and certificate into one of the four real types, and whatever
    // it picked was taken downstream as fact.
    @Guide(
        description: "The content type",
        .anyOf(["receipt", "event", "article", "note", "ticket", "other"])
    )
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
@Generable(description: "Fields extracted from a movie or travel ticket")
private struct TicketExtraction {
    @Guide(description: "Ticket type", .anyOf(["movie", "train", "bus", "event"]))
    var ticketType: String
    @Guide(description: "Film title, or journey description e.g. 'Chennai Central to Bengaluru'")
    var title: String
    @Guide(description: "Venue or operator name — theater name, or train/bus name and number")
    var venueOrOperator: String
    @Guide(description: "Showtime or departure date and time as printed, or empty if absent")
    var dateTime: String
    @Guide(description: "Seat and screen for movies, or coach and seat/berth for trains, as printed")
    var seatDetails: String
    @Guide(description: "Booking ID, PNR, or order number as printed, or empty if absent")
    var referenceNumber: String
    @Guide(description: "Price or fare as printed, digits only, or empty if absent")
    var price: String
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

        case "ticket":
            let session = LanguageModelSession(
                instructions: "Extract ticket fields exactly as they appear in the text. Do not invent values."
            )
            let ticket = try await session.respond(
                to: content,
                generating: TicketExtraction.self
            ).content
            return ItemEnrichment(
                summary: "\(ticket.title) — \(ticket.dateTime)",
                tags: [ticket.ticketType],
                extraction: ItemExtraction(
                    category: "ticket",
                    ticketType: ticket.ticketType,
                    ticketTitle: ticket.title,
                    venueOrOperator: ticket.venueOrOperator.isEmpty ? nil : ticket.venueOrOperator,
                    ticketDateTime: ticket.dateTime.isEmpty ? nil : ticket.dateTime,
                    seatDetails: ticket.seatDetails.isEmpty ? nil : ticket.seatDetails,
                    referenceNumber: ticket.referenceNumber.isEmpty ? nil : ticket.referenceNumber,
                    price: ticket.price.isEmpty ? nil : ticket.price
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
                    // "other" stays "other": collapsing it into "note" would
                    // hand it back the benefit of the doubt this branch exists
                    // to withhold.
                    category: Self.storedCategory(for: category),
                    shortTitle: note.shortTitle
                )
            )
        }
    }

    /// Category persisted for anything the specific extractors didn't handle.
    private static func storedCategory(for classified: String) -> String {
        switch classified {
        case "article": "link"
        case "other": "other"
        default: "note"
        }
    }

    private func classify(_ content: String, kind: ShelfItemKind) async throws -> String {
        // Links are links; only free text and OCR output need routing.
        if kind == .link { return "article" }

        let session = LanguageModelSession(
            instructions: "Classify the text of a saved item. A receipt shows purchased items or amounts paid. A ticket is a movie, train, bus, or event booking with a seat, fare, or booking reference. An event has a date and a happening to attend. An article is saved web content. A note is something the person wrote. Use other for anything else — an ordinary photograph, a certificate or award, an ID card, a screenshot of an app. Do not stretch a document to fit a type it is not; other is the right answer more often than any single type."
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
