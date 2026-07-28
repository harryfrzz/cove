import Accelerate
import Foundation
import Observation

/// The carousel's shelf groups. Image items are assigned by CLIP zero-shot
/// classification: each bucket has a text prompt, embedded once with the
/// MobileCLIP2 text encoder, and every item's stored embedding is matched to
/// the nearest prompt by dot product. Notes and links group by kind.
enum ShelfBucket: String, CaseIterable, Identifiable, Sendable {
    case receipts
    case events
    case food
    case places
    case documents
    case notes
    case links
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .receipts: "Receipts"
        case .events: "Events"
        case .food: "Food"
        case .places: "Places"
        case .documents: "Documents"
        case .notes: "Notes"
        case .links: "Links"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .receipts: "receipt"
        case .events: "ticket"
        case .food: "fork.knife"
        case .places: "map"
        case .documents: "doc.text"
        case .notes: "note.text"
        case .links: "link"
        case .other: "square.stack"
        }
    }

    /// CLIP zero-shot prompt ensemble; empty for kind-based buckets. Several
    /// phrasings are embedded and averaged — single prompts leave bucket
    /// scores close enough that fp jitter can flip the argmax between runs.
    var prompts: [String] {
        switch self {
        case .receipts: [
            "a photo of a shopping receipt",
            "a store receipt with a list of prices and a total",
            "an invoice or bill with amounts of money",
        ]
        case .events: [
            "a ticket for a concert or event",
            "an event poster with a date and venue",
            "an invitation to an event",
        ]
        case .food: [
            "a photo of a plate of food",
            "a photo of drinks or a meal at a restaurant",
            "a restaurant menu with dishes",
        ]
        case .places: [
            "a photo of a landscape or scenery",
            "a photo of a city, building, or travel destination",
            "a map of a place",
        ]
        case .documents: [
            "a screenshot of a mobile app user interface",
            "a screenshot of a document or article with text",
            "a screenshot of a chat conversation",
        ]
        case .notes, .links, .other: []
        }
    }
}

/// Computes bucket prototype embeddings once per launch and groups shelf
/// items by embedding similarity. Falls back to `.other` until prototypes are
/// ready or when an item has no comparable embedding.
@MainActor
@Observable
final class ShelfCategorizer {
    static let shared = ShelfCategorizer()

    /// Below this cosine similarity an image matches no bucket convincingly
    /// and lands in "Everything else". Correct zero-shot matches on this
    /// model sit around 0.19–0.29; mismatches around 0.05–0.15.
    private static let similarityFloor: Float = 0.12

    private(set) var isReady = false
    private var prototypes: [(bucket: ShelfBucket, vector: [Float])] = []
    private var isPreparing = false

    private init() {}

    func prepareIfNeeded() async {
        guard !isReady, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        let embeddings = AIServices.current.embeddings
        var computed: [(ShelfBucket, [Float])] = []
        for bucket in ShelfBucket.allCases {
            let prompts = bucket.prompts
            guard !prompts.isEmpty else { continue }

            // Average the ensemble, then renormalize so dot products stay
            // comparable across buckets.
            var sum: [Float]?
            for prompt in prompts {
                guard let vector = try? await embeddings.embed(text: prompt) else { continue }
                if var accumulated = sum {
                    vDSP.add(accumulated, vector, result: &accumulated)
                    sum = accumulated
                } else {
                    sum = vector
                }
            }
            guard var mean = sum else { continue }
            var norm: Float = 0
            vDSP_svesq(mean, 1, &norm, vDSP_Length(mean.count))
            norm = sqrt(norm)
            guard norm > 0 else { continue }
            vDSP.divide(mean, norm, result: &mean)
            computed.append((bucket, mean))
        }
        guard !computed.isEmpty else { return }
        prototypes = computed
        isReady = true
    }

    func bucket(for item: ShelfItem) -> ShelfBucket {
        switch item.kind {
        case .text:
            return .notes
        case .link:
            return .links
        case .screenshot, .image:
            // What the extraction *read off the item* beats what the image
            // merely looks like. A receipt that says "receipt" is settled; the
            // prototype match below is a fuzzy zero-shot similarity and only
            // gets a say when there's nothing better.
            //
            // This is also what rescues an item with no embedding at all —
            // seeded demo passes, or anything whose embedding pass failed —
            // which would otherwise land in "Everything else" forever.
            if let bucket = Self.bucket(forExtraction: item.extraction) {
                return bucket
            }

            guard isReady,
                  let vector = item.embedding ?? item.textEmbedding else {
                return .other
            }

            var bestBucket = ShelfBucket.other
            var bestScore = Self.similarityFloor
            for prototype in prototypes where prototype.vector.count == vector.count {
                var dot: Float = 0
                vDSP_dotpr(prototype.vector, 1, vector, 1, &dot, vDSP_Length(vector.count))
                if dot > bestScore {
                    bestScore = dot
                    bestBucket = prototype.bucket
                }
            }
            return bestBucket
        }
    }

    /// The shelf a structured extraction puts an item on, or `nil` when the
    /// extraction says nothing a shelf maps to and the prototypes should decide.
    static func bucket(forExtraction extraction: ItemExtraction?) -> ShelfBucket? {
        // A receipt/event/ticket label only earns its shelf if the fields back
        // it up; otherwise defer to the prototypes, which are better at telling
        // a certificate from a boarding pass than a forced label is.
        if let extraction,
           ["receipt", "event", "ticket"].contains(extraction.category),
           !extraction.describesAPass {
            return nil
        }

        return switch extraction?.category {
        case "receipt": .receipts
        // Concerts, flights, trains and cinema all live on the same shelf.
        case "event", "ticket": .events
        case "article": .documents
        case "note": .notes
        default: nil
        }
    }

    /// Groups items into non-empty buckets in fixed display order, items
    /// newest-first inside each group.
    func group(_ items: [ShelfItem]) -> [(bucket: ShelfBucket, items: [ShelfItem])] {
        var grouped: [ShelfBucket: [ShelfItem]] = [:]
        for item in items {
            grouped[bucket(for: item), default: []].append(item)
        }
        return ShelfBucket.allCases.compactMap { bucket in
            guard let bucketItems = grouped[bucket], !bucketItems.isEmpty else { return nil }
            return (bucket, bucketItems)
        }
    }
}
