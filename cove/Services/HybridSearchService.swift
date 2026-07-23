import Accelerate
import Foundation
import SwiftData

/// Hybrid retrieval over the local shelf: CLIP semantic similarity fused with
/// literal keyword matching via reciprocal-rank fusion.
///
/// Pure vector search misses queries for text *inside* an image (merchant
/// names, order numbers) because CLIP reads scenes, not strings; pure keyword
/// search misses "the receipt from the coffee place". Fusing both ranked
/// lists covers each one's blind spot. Brute force over every stored vector
/// is deliberate: at personal-shelf scale (hundreds to low thousands) a vDSP
/// dot-product sweep is instant and dependency-free.
struct HybridSearchService: SearchService {
    let embeddings: any EmbeddingService

    // MARK: Tuning
    /// RRF constant: standard value from the literature; softens rank decay.
    private static let rrfK: Double = 60
    /// Keyword list weight slightly above semantic — a literal hit on a
    /// merchant name or order number should beat a loose scene match.
    private static let keywordWeight: Double = 1.2
    private static let semanticWeight: Double = 1.0
    /// Relevance floor: items below this cosine similarity with no keyword
    /// hit are dropped instead of padding the results.
    private static let cosineFloor: Float = 0.18

    @MainActor
    func search(_ query: String, in items: [ShelfItem]) async throws -> [ShelfItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        let queryEmbedding = try? await embeddings.embed(text: trimmed)

        var semanticScores: [PersistentIdentifier: Float] = [:]
        var keywordScores: [PersistentIdentifier: Double] = [:]

        for item in items {
            if let queryEmbedding {
                var best: Float = -1
                for stored in [item.embedding, item.textEmbedding] {
                    guard let stored, stored.count == queryEmbedding.count else { continue }
                    var dot: Float = 0
                    vDSP_dotpr(stored, 1, queryEmbedding, 1, &dot, vDSP_Length(stored.count))
                    best = max(best, dot)
                }
                if best > -1 {
                    semanticScores[item.persistentModelID] = best
                }
            }

            let keyword = Self.keywordScore(query: trimmed, in: item.searchableText)
            if keyword > 0 {
                keywordScores[item.persistentModelID] = keyword
            }
        }

        let semanticRanked = semanticScores.sorted { $0.value > $1.value }.map(\.key)
        let keywordRanked = keywordScores.sorted { $0.value > $1.value }.map(\.key)

        var fused: [PersistentIdentifier: Double] = [:]
        for (rank, id) in semanticRanked.enumerated() {
            fused[id, default: 0] += Self.semanticWeight / (Self.rrfK + Double(rank + 1))
        }
        for (rank, id) in keywordRanked.enumerated() {
            fused[id, default: 0] += Self.keywordWeight / (Self.rrfK + Double(rank + 1))
        }

        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.persistentModelID, $0) })
        let ordered = fused.sorted { $0.value > $1.value }.compactMap { itemsByID[$0.key] }

        return ordered.filter { item in
            let id = item.persistentModelID
            let hasKeywordHit = keywordScores[id] != nil
            let passesSemanticFloor = (semanticScores[id] ?? -1) >= Self.cosineFloor
            return hasKeywordHit || passesSemanticFloor
        }
    }

    /// Fraction of query terms found literally in the item text, with a bonus
    /// when the whole query appears as a phrase. Case- and diacritic-folded.
    private static func keywordScore(query: String, in text: String) -> Double {
        let foldedText = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let foldedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)

        let terms = foldedQuery
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
        guard !terms.isEmpty else {
            return foldedText.contains(foldedQuery) ? 1 : 0
        }

        let matched = terms.filter { foldedText.contains($0) }.count
        var score = Double(matched) / Double(terms.count)
        if terms.count > 1, foldedText.contains(foldedQuery) {
            score += 0.5
        }
        return score
    }
}
