import Foundation
import Testing
@testable import cove

@Suite struct ExtractionCodingTests {
    @Test func extractionRoundTripsThroughShelfItem() {
        let item = ShelfItem(kind: .screenshot, title: "Receipt")
        let extraction = ItemExtraction(
            category: "receipt",
            merchant: "North Star Market",
            total: "22.50",
            currency: "$",
            date: "22 July 2026",
            expenseCategory: "groceries"
        )
        item.extraction = extraction
        #expect(item.extraction == extraction)
        #expect(item.extractionJSON?.contains("North Star Market") == true)

        item.extraction = nil
        #expect(item.extractionJSON == nil)
    }

    @Test func corruptJSONDecodesAsNil() {
        let item = ShelfItem(kind: .text, title: "note")
        item.extractionJSON = "{not json"
        #expect(item.extraction == nil)
    }

    @Test func truncationKeepsHeadAndTail() {
        let head = String(repeating: "H", count: 3000)
        let tail = String(repeating: "T", count: 1000)
        let result = FoundationModelsService.truncated(head + tail)
        #expect(result.hasPrefix("HHH"))
        #expect(result.hasSuffix("TTT"))
        #expect(result.count < 3400)

        let short = "already short"
        #expect(FoundationModelsService.truncated(short) == short)
    }
}
