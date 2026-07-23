import Testing
import UIKit
@testable import cove

/// Runs the real Core ML encoders (CPU on simulator). Slow-ish but proves the
/// bundled models load and behave.
@Suite struct EmbeddingTests {
    @Test func textEmbeddingIsNormalizedAndDeterministic() async throws {
        let service = MobileCLIPEmbeddingService.shared
        let first = try await service.embed(text: "receipt from the coffee place")
        let second = try await service.embed(text: "receipt from the coffee place")

        let norm = first.reduce(0) { $0 + $1 * $1 }.squareRoot()
        #expect(abs(norm - 1) < 0.01)
        #expect(first == second)
    }

    @Test func imageEmbeddingMatchesTextDimension() async throws {
        let service = MobileCLIPEmbeddingService.shared
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 500))
        let image = renderer.image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 500))
        }

        let imageVector = try await service.embed(image: image)
        let textVector = try await service.embed(text: "anything")

        #expect(imageVector.count == textVector.count)
        let dimension = try #require(await service.embeddingDimension)
        #expect(imageVector.count == dimension)

        let norm = imageVector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        #expect(abs(norm - 1) < 0.01)
    }

    @Test func embeddingBlobRoundTrips() {
        let vector: [Float] = [0.25, -0.5, 1, 0]
        let data = ShelfItem.blob(from: vector)
        #expect(ShelfItem.floats(from: data) == vector)
        #expect(ShelfItem.floats(from: nil) == nil)
        #expect(ShelfItem.floats(from: Data([0x01, 0x02, 0x03])) == nil)
    }
}
