import UIKit
import Vision

/// Real on-device OCR backed by the modern Vision Swift API.
///
/// Uses `RecognizeDocumentsRequest` (iOS 26) so receipts keep their line and
/// table structure, and falls back to `RecognizeTextRequest` at the accurate
/// recognition level if the document request fails. "No text found" returns an
/// empty string, never an error.
struct VisionOCRService: OCRService {
    /// Longest image side handed to Vision. Screenshots above this are
    /// downscaled; below it small receipt text starts dropping out, above it
    /// latency grows with no accuracy gain.
    static let maximumImageExtent: CGFloat = 2048

    func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = normalizedCGImage(from: image) else { return "" }

        do {
            var request = RecognizeDocumentsRequest()
            request.textRecognitionOptions.recognitionLanguages = Self.recognitionLanguages
            request.textRecognitionOptions.useLanguageCorrection = true
            let observations = try await request.perform(on: cgImage, orientation: nil)
            let text = observations.map { format(document: $0.document) }.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        } catch {
            // Fall through to plain text recognition.
        }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = Self.recognitionLanguages
        let observations = try await request.perform(on: cgImage, orientation: nil)
        return observations.map(\.transcript).joined(separator: "\n")
    }

    /// English plus the device language, deduplicated.
    static var recognitionLanguages: [Locale.Language] {
        let english = Locale.Language(identifier: "en-US")
        let device = Locale.current.language
        if device.languageCode == english.languageCode {
            return [english]
        }
        return [english, device]
    }

    private func format(document: DocumentObservation.Container) -> String {
        var parts: [String] = []
        let transcript = document.text.transcript
        if !transcript.isEmpty {
            parts.append(transcript)
        }
        // Re-render tables row-by-row so downstream extraction sees columns.
        for table in document.tables {
            let rows = table.rows.map { row in
                row.map { $0.content.text.transcript.replacingOccurrences(of: "\n", with: " ") }
                    .joined(separator: " | ")
            }
            if !rows.isEmpty {
                parts.append(rows.joined(separator: "\n"))
            }
        }
        return parts.joined(separator: "\n")
    }

    /// Fixes UIImage orientation and downscales very large screenshots.
    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longest = max(pixelSize.width, pixelSize.height)
        let ratio = longest > Self.maximumImageExtent ? Self.maximumImageExtent / longest : 1
        let targetSize = CGSize(
            width: (pixelSize.width * ratio).rounded(),
            height: (pixelSize.height * ratio).rounded()
        )

        if ratio == 1, image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let redrawn = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return redrawn.cgImage
    }
}
