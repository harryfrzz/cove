import SwiftUI
import UIKit

protocol EmbeddingService: Sendable {
    func embed(image: UIImage) async throws -> [Float]
    func embed(text: String) async throws -> [Float]
}

protocol OCRService: Sendable {
    func recognizeText(in image: UIImage) async throws -> String
}

protocol SummarizationService: Sendable {
    func summarize(_ text: String) async throws -> String
}

protocol ImageUnderstandingService: Sendable {
    func describe(image: UIImage) async throws -> String
    func answer(question: String, about image: UIImage) async throws -> String
}

protocol SearchService: Sendable {
    @MainActor
    func search(_ query: String, in items: [ShelfItem]) async throws -> [ShelfItem]
}

/// Runtime switch between the real on-device stack and the Phase 1 mocks.
/// Toggle via the `--use-mock-ai` launch argument or the debug diagnostics
/// screen (UserDefaults; takes effect on next launch because services are
/// injected once into the SwiftUI environment).
enum AIServiceMode {
    static let mockDefaultsKey = "cove.useMockAI"

    static var useMock: Bool {
        if ProcessInfo.processInfo.arguments.contains("--use-mock-ai") {
            return true
        }
        return UserDefaults.standard.bool(forKey: mockDefaultsKey)
    }
}

struct AIServices: Sendable {
    let embeddings: any EmbeddingService
    let ocr: any OCRService
    let summarization: any SummarizationService
    let imageUnderstanding: any ImageUnderstandingService
    let search: any SearchService
    let extraction: any StructuredExtractionService

    static let mock: AIServices = {
        let mock = MockAIServices()
        return AIServices(
            embeddings: mock,
            ocr: mock,
            summarization: mock,
            imageUnderstanding: mock,
            search: mock,
            extraction: mock
        )
    }()

    /// Real on-device stack. `ImageUnderstandingService` intentionally stays
    /// mocked this phase (VLM is out of scope).
    static let onDevice: AIServices = {
        let embeddings = MobileCLIPEmbeddingService.shared
        let foundationModels = FoundationModelsService()
        return AIServices(
            embeddings: embeddings,
            ocr: VisionOCRService(),
            summarization: foundationModels,
            imageUnderstanding: MockAIServices(),
            search: HybridSearchService(embeddings: embeddings),
            extraction: foundationModels
        )
    }()

    static var current: AIServices {
        AIServiceMode.useMock ? .mock : .onDevice
    }

    /// Version tag persisted with every stored embedding so a future model
    /// swap can detect and re-index stale vectors.
    static var currentEmbeddingModelVersion: String {
        AIServiceMode.useMock ? "mock-64" : MobileCLIPEmbeddingService.modelVersion
    }
}

private struct AIServicesEnvironmentKey: EnvironmentKey {
    static let defaultValue = AIServices.mock
}

extension EnvironmentValues {
    var aiServices: AIServices {
        get { self[AIServicesEnvironmentKey.self] }
        set { self[AIServicesEnvironmentKey.self] = newValue }
    }
}
