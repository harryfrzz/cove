#if DEBUG
import FoundationModels
import SwiftUI
import UIKit

/// Debug harness: proves the on-device stack works on this hardware and
/// measures it. Not compiled into release builds.
struct AIDiagnosticsView: View {
    @AppStorage(AIServiceMode.mockDefaultsKey) private var useMockServices = false
    @State private var report: [ReportLine] = []
    @State private var isRunning = false

    struct ReportLine: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let ok: Bool
    }

    var body: some View {
        List {
            Section("Service mode") {
                Toggle("Use Phase 1 mocks", isOn: $useMockServices)
                Text("Takes effect at next launch. The `--use-mock-ai` launch argument forces mocks regardless.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Language model") {
                LabeledContent("Availability", value: languageModelStatus)
            }

            Section {
                Button(isRunning ? "Running…" : "Run on-device checks") {
                    Task { await runChecks() }
                }
                .disabled(isRunning)

                ForEach(report) { line in
                    LabeledContent {
                        Text(line.value)
                            .font(.callout.monospaced())
                            .foregroundStyle(line.ok ? .primary : Color.red)
                    } label: {
                        Text(line.label)
                    }
                }
            } header: {
                Text("MobileCLIP2 + Vision + tokenizer")
            } footer: {
                Text("Timings are per call after a warm-up run, on this device, compute units = all.")
            }
        }
        .navigationTitle("AI Diagnostics")
    }

    private var languageModelStatus: String {
        FoundationModelsService.availabilityError()?.localizedDescription ?? "Available"
    }

    private func runChecks() async {
        isRunning = true
        report = []
        defer { isRunning = false }

        // 1. Tokenizer parity against the Python reference fixtures.
        do {
            let tokenizer = try CLIPTokenizer.bundled()
            guard let fixtureURL = Bundle.main.url(
                forResource: "tokenizer-fixtures", withExtension: "json"
            ) else {
                throw CLIPTokenizer.TokenizerError.assetMissing
            }
            struct Fixture: Decodable {
                let text: String
                let ids: [Int32]
            }
            let fixtures = try JSONDecoder().decode(
                [Fixture].self, from: Data(contentsOf: fixtureURL)
            )
            let mismatches = fixtures.filter { tokenizer.encodeFull($0.text) != $0.ids }
            append(
                "Tokenizer parity",
                mismatches.isEmpty
                    ? "\(fixtures.count)/\(fixtures.count) fixtures match"
                    : "MISMATCH: \(mismatches.map(\.text).joined(separator: "; "))",
                ok: mismatches.isEmpty
            )
        } catch {
            append("Tokenizer parity", "failed: \(error.localizedDescription)", ok: false)
        }

        // 2. Both encoders load, produce normalized vectors, and are timed.
        let embeddings = MobileCLIPEmbeddingService.shared
        let testImage = Self.syntheticImage()
        do {
            let loadStart = Date.now
            let warmup = try await embeddings.embed(image: testImage)
            append(
                "Image encoder",
                "dim \(warmup.count) · load+first run \(Self.ms(since: loadStart))",
                ok: true
            )
            let norm = warmup.reduce(0) { $0 + $1 * $1 }.squareRoot()
            append("Image embedding norm", String(format: "%.5f", norm), ok: abs(norm - 1) < 0.01)

            let imageStart = Date.now
            for _ in 0..<5 { _ = try await embeddings.embed(image: testImage) }
            append("Image embed (avg of 5)", Self.ms(since: imageStart, dividedBy: 5), ok: true)

            _ = try await embeddings.embed(text: "warm up")
            let textStart = Date.now
            for _ in 0..<5 {
                _ = try await embeddings.embed(text: "receipt from the coffee place")
            }
            append("Text embed (avg of 5)", Self.ms(since: textStart, dividedBy: 5), ok: true)
        } catch {
            append("Embeddings", "failed: \(error.localizedDescription)", ok: false)
        }

        // 3. OCR on a rendered receipt-like image.
        do {
            let ocr = VisionOCRService()
            let receipt = Self.syntheticReceiptImage()
            let start = Date.now
            let text = try await ocr.recognizeText(in: receipt)
            let foundTotal = text.contains("22.50")
            append(
                "Vision OCR",
                "\(Self.ms(since: start)) · \(text.count) chars\(foundTotal ? "" : " · total NOT found")",
                ok: foundTotal
            )
        } catch {
            append("Vision OCR", "failed: \(error.localizedDescription)", ok: false)
        }

        // 4. Guided generation, if the system model is available.
        if FoundationModelsService.availabilityError() == nil {
            do {
                let service = FoundationModelsService()
                let start = Date.now
                let enrichment = try await service.enrich(
                    text: "NORTH STAR MARKET\nCoffee beans $18.00\nOat milk $4.50\nTotal $22.50\n22 July 2026",
                    kind: .screenshot
                )
                let merchantOK = enrichment.extraction?.merchant?.localizedCaseInsensitiveContains("north star") == true
                append(
                    "Guided extraction",
                    "\(Self.ms(since: start)) · \(enrichment.extraction?.category ?? "none") · \(enrichment.extraction?.merchant ?? "-")",
                    ok: merchantOK
                )
            } catch {
                append("Guided extraction", "failed: \(error.localizedDescription)", ok: false)
            }
        } else {
            append("Guided extraction", "skipped — model unavailable", ok: true)
        }
    }

    private func append(_ label: String, _ value: String, ok: Bool) {
        report.append(ReportLine(label: label, value: value, ok: ok))
    }

    private static func ms(since start: Date, dividedBy count: Double = 1) -> String {
        String(format: "%.0f ms", -start.timeIntervalSinceNow * 1000 / count)
    }

    private static func syntheticImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
        return renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 96, y: 96, width: 320, height: 320))
        }
    }

    private static func syntheticReceiptImage() -> UIImage {
        let size = CGSize(width: 600, height: 800)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let text = "NORTH STAR MARKET\n\nCoffee beans      $18.00\nOat milk           $4.50\n\nTotal             $22.50\n\n22 July 2026"
            text.draw(
                in: CGRect(x: 48, y: 60, width: 504, height: 680),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 28, weight: .medium),
                    .foregroundColor: UIColor.black
                ]
            )
        }
    }
}
#endif
