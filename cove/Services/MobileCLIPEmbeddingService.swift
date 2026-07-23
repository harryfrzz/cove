import Accelerate
import CoreML
import CoreVideo
import UIKit

/// On-device MobileCLIP2-S0 embeddings (image + text encoders converted to
/// Core ML by tools/mobileclip2/convert.py, parity-tested against the PyTorch
/// reference).
///
/// An actor so inference is serialized: concurrent Core ML calls on a phone
/// cause memory spikes and thermal throttling, not speedups. Both models load
/// once, lazily, on first use.
actor MobileCLIPEmbeddingService: EmbeddingService {
    static let shared = MobileCLIPEmbeddingService()

    /// Bumped whenever the bundled model changes; persisted next to every
    /// stored embedding so stale vectors can be detected and re-indexed.
    static let modelVersion = "mobileclip2-s0-v1"

    enum EmbeddingError: LocalizedError {
        case modelMissing(String)
        case unexpectedOutput
        case imageConversionFailed

        var errorDescription: String? {
            switch self {
            case .modelMissing(let name):
                "The on-device model \(name) is missing from the app bundle."
            case .unexpectedOutput:
                "The embedding model returned an unexpected output."
            case .imageConversionFailed:
                "The image could not be prepared for the embedding model."
            }
        }
    }

    private struct LoadedModels {
        let image: MLModel
        let text: MLModel
        let tokenizer: CLIPTokenizer
        let imageInputSize: Int
        let embeddingDimension: Int
    }

    private var loaded: LoadedModels?

    /// The embedding dimension read from the compiled model, available after
    /// the first load. Never hardcode this elsewhere.
    private(set) var embeddingDimension: Int?

    func embed(image: UIImage) async throws -> [Float] {
        let models = try await load()
        guard let pixelBuffer = Self.pixelBuffer(
            from: image,
            sideLength: models.imageInputSize
        ) else {
            throw EmbeddingError.imageConversionFailed
        }

        let input = try MLDictionaryFeatureProvider(
            dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)]
        )
        let output = try await models.image.prediction(from: input)
        return try Self.embeddingVector(from: output, dimension: models.embeddingDimension)
    }

    func embed(text: String) async throws -> [Float] {
        let models = try await load()
        let tokens = models.tokenizer.encodeFull(text)

        let array = try MLMultiArray(
            shape: [1, NSNumber(value: tokens.count)],
            dataType: .int32
        )
        for (index, token) in tokens.enumerated() {
            array[index] = NSNumber(value: token)
        }

        let input = try MLDictionaryFeatureProvider(
            dictionary: ["text": MLFeatureValue(multiArray: array)]
        )
        let output = try await models.text.prediction(from: input)
        return try Self.embeddingVector(from: output, dimension: models.embeddingDimension)
    }

    // MARK: - Loading

    private func load() async throws -> LoadedModels {
        if let loaded { return loaded }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        let imageModel = try await MLModel.load(
            contentsOf: Self.bundledModelURL(named: "MobileCLIP2S0ImageEncoder"),
            configuration: configuration
        )
        let textModel = try await MLModel.load(
            contentsOf: Self.bundledModelURL(named: "MobileCLIP2S0TextEncoder"),
            configuration: configuration
        )
        let tokenizer = try CLIPTokenizer.bundled()

        guard
            let imageConstraint = imageModel.modelDescription
                .inputDescriptionsByName["image"]?.imageConstraint,
            let outputConstraint = imageModel.modelDescription
                .outputDescriptionsByName["embedding"]?.multiArrayConstraint,
            let dimension = outputConstraint.shape.last?.intValue
        else {
            throw EmbeddingError.unexpectedOutput
        }

        let models = LoadedModels(
            image: imageModel,
            text: textModel,
            tokenizer: tokenizer,
            imageInputSize: imageConstraint.pixelsWide,
            embeddingDimension: dimension
        )
        loaded = models
        embeddingDimension = dimension
        return models
    }

    private static func bundledModelURL(named name: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            throw EmbeddingError.modelMissing(name)
        }
        return url
    }

    private static func embeddingVector(
        from output: MLFeatureProvider,
        dimension: Int
    ) throws -> [Float] {
        guard let array = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw EmbeddingError.unexpectedOutput
        }
        let values = MLShapedArray<Float>(array).scalars
        guard values.count == dimension else {
            throw EmbeddingError.unexpectedOutput
        }
        // The exported graph already L2-normalizes; renormalize defensively so
        // stored vectors always dot-product as cosine similarity.
        var norm: Float = 0
        vDSP_svesq(values, 1, &norm, vDSP_Length(values.count))
        norm = sqrt(norm)
        guard norm > 0 else { throw EmbeddingError.unexpectedOutput }
        var scale = 1 / norm
        var normalized = [Float](repeating: 0, count: values.count)
        vDSP_vsmul(values, 1, &scale, &normalized, 1, vDSP_Length(values.count))
        return normalized
    }

    // MARK: - Preprocessing

    /// MobileCLIP2-S0 preprocessing: resize the shortest side to the model's
    /// input size, center crop to a square, RGB in [0,1]. The [0,1] scaling is
    /// baked into the Core ML model's image input, so this only has to deliver
    /// pixels. (Verified against open_clip's registry: mean 0, std 1 — not the
    /// OpenAI CLIP normalization.)
    private static func pixelBuffer(from image: UIImage, sideLength: Int) -> CVPixelBuffer? {
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }

        let side = CGFloat(sideLength)
        let scaleFactor = side / min(pixelSize.width, pixelSize.height)
        let scaledSize = CGSize(
            width: pixelSize.width * scaleFactor,
            height: pixelSize.height * scaleFactor
        )
        let drawOrigin = CGPoint(
            x: (side - scaledSize.width) / 2,
            y: (side - scaledSize.height) / 2
        )

        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            sideLength,
            sideLength,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: sideLength,
            height: sideLength,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        UIGraphicsPushContext(context)
        // CGContext has a bottom-left origin; flip so UIImage draws upright.
        context.translateBy(x: 0, y: side)
        context.scaleBy(x: 1, y: -1)
        image.draw(in: CGRect(origin: drawOrigin, size: scaledSize))
        UIGraphicsPopContext()

        return buffer
    }
}
