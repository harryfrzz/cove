import Foundation
import SwiftData

enum ShelfItemKind: String, Codable, CaseIterable, Identifiable {
    case screenshot
    case image
    case link
    case text

    var id: String { rawValue }

    var label: String {
        switch self {
        case .screenshot: "Screenshot"
        case .image: "Image"
        case .link: "Link"
        case .text: "Note"
        }
    }

    var systemImage: String {
        switch self {
        case .screenshot: "rectangle.inset.filled"
        case .image: "photo"
        case .link: "link"
        case .text: "note.text"
        }
    }
}

enum ShelfProcessingState: String, Codable, CaseIterable {
    case queued
    case processing
    case ready
    case failed
}

@Model
final class ShelfItem {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var kindRawValue: String
    var title: String
    var userNote: String?
    @Attribute(.externalStorage) var imageData: Data?
    var linkURL: URL?
    var linkTitle: String?
    var linkHost: String?
    var extractedText: String?
    var summary: String?
    var tags: [String]
    var embeddingData: Data?
    var textEmbeddingData: Data?
    var embeddingDimension: Int?
    var embeddingModelVersion: String?
    var categoryRawValue: String?
    var extractionJSON: String?
    var failureMessage: String?
    /// PHAsset localIdentifier when the item was indexed from the photo
    /// library; used to avoid importing the same asset twice.
    var assetIdentifier: String?
    /// Manually pinned to the Wallet page (receipts/tickets also appear
    /// there automatically via classification).
    var isInWallet: Bool = false
    var processingStateRawValue: String

    var kind: ShelfItemKind {
        get { ShelfItemKind(rawValue: kindRawValue) ?? .text }
        set { kindRawValue = newValue.rawValue }
    }

    var processingState: ShelfProcessingState {
        get { ShelfProcessingState(rawValue: processingStateRawValue) ?? .queued }
        set { processingStateRawValue = newValue.rawValue }
    }

    /// Image (or primary) embedding as a compact Float32 blob.
    var embedding: [Float]? {
        get { Self.floats(from: embeddingData) }
        set { embeddingData = Self.blob(from: newValue) }
    }

    /// Embedding of the enriched text (title, note, OCR text, summary).
    var textEmbedding: [Float]? {
        get { Self.floats(from: textEmbeddingData) }
        set { textEmbeddingData = Self.blob(from: newValue) }
    }

    static func floats(from data: Data?) -> [Float]? {
        guard let data, !data.isEmpty, data.count % MemoryLayout<Float32>.size == 0 else {
            return nil
        }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float32.self)) }
    }

    static func blob(from floats: [Float]?) -> Data? {
        guard let floats else { return nil }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    var searchableText: String {
        [
            title,
            userNote,
            linkTitle,
            linkHost,
            extractedText,
            summary,
            tags.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        kind: ShelfItemKind,
        title: String,
        userNote: String? = nil,
        imageData: Data? = nil,
        linkURL: URL? = nil,
        linkTitle: String? = nil,
        linkHost: String? = nil,
        extractedText: String? = nil,
        summary: String? = nil,
        tags: [String] = [],
        embedding: [Float]? = nil,
        assetIdentifier: String? = nil,
        processingState: ShelfProcessingState = .queued
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kindRawValue = kind.rawValue
        self.title = title
        self.userNote = userNote
        self.imageData = imageData
        self.linkURL = linkURL
        self.linkTitle = linkTitle
        self.linkHost = linkHost
        self.extractedText = extractedText
        self.summary = summary
        self.tags = tags
        self.embeddingData = Self.blob(from: embedding)
        self.assetIdentifier = assetIdentifier
        self.processingStateRawValue = processingState.rawValue
    }
}
