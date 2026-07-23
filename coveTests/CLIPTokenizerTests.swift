import Foundation
import Testing
@testable import cove

@Suite struct CLIPTokenizerTests {
    private struct Fixture: Decodable {
        let text: String
        let ids: [Int32]
    }

    /// Token-ID parity against the Python reference (open_clip SimpleTokenizer)
    /// for every fixture exported by tools/mobileclip2/convert.py.
    @Test func matchesReferenceFixtures() throws {
        let tokenizer = try CLIPTokenizer.bundled()
        let url = try #require(
            Bundle.main.url(forResource: "tokenizer-fixtures", withExtension: "json")
        )
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        #expect(!fixtures.isEmpty)

        for fixture in fixtures {
            let ids = tokenizer.encodeFull(fixture.text)
            #expect(ids == fixture.ids, "mismatch for: \(fixture.text)")
        }
    }

    @Test func producesFixedLengthWithSpecialTokens() throws {
        let tokenizer = try CLIPTokenizer.bundled()
        let ids = tokenizer.encodeFull("hello world")
        #expect(ids.count == tokenizer.contextLength)
        #expect(ids.first == tokenizer.sotToken)
        #expect(ids.contains(tokenizer.eotToken))
    }

    @Test func truncatesLongInputKeepingEOT() throws {
        let tokenizer = try CLIPTokenizer.bundled()
        let long = Array(repeating: "tokenization", count: 300).joined(separator: " ")
        let ids = tokenizer.encodeFull(long)
        #expect(ids.count == tokenizer.contextLength)
        #expect(ids.last == tokenizer.eotToken)
    }

    @Test func emptyInputIsJustSpecialTokens() throws {
        let tokenizer = try CLIPTokenizer.bundled()
        let ids = tokenizer.encodeFull("   ")
        #expect(ids[0] == tokenizer.sotToken)
        #expect(ids[1] == tokenizer.eotToken)
        #expect(ids[2...].allSatisfy { $0 == 0 })
    }
}
