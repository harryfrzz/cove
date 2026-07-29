import FoundationModels
import SwiftData
import SwiftUI
import UIKit

/// What Cove is running on, and the only two levers there are over it.
///
/// Worth being plain about, because "download the model" means two different
/// things here and neither is a download Cove can start:
///
/// - The **embedding encoders** are compiled into the app binary (~143 MB of
///   it). They are never fetched, so they cannot go missing at runtime and
///   cannot be repaired by re-fetching. What this screen can do is load them
///   early, drop and re-read them from the bundle, and put the shelf back
///   through them.
/// - The **language model** is Apple's, shared by the whole system. iOS owns
///   its download and eligibility; an app can read the availability and send
///   you to Settings, and that is the entire surface. `.modelNotReady` means
///   iOS is already fetching it.
///
/// So: real status for both, real actions where actions exist, and a straight
/// answer where they don't.
struct ModelSetupView: View {
    @Query private var items: [ShelfItem]

    @State private var embedding: MobileCLIPEmbeddingService.Readiness?
    @State private var embeddingError: String?
    @State private var isPreparing = false
    @State private var loadDuration: Duration?

    @State private var languageModel: FoundationModelsService.ModelUnavailable?

    @State private var reindexedCount: Int?
    @State private var isReindexing = false

    private var readyItemCount: Int {
        items.filter { $0.processingState == .ready }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                embeddingCard
                languageCard
                privacyNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, CoveTabBar.occupiedHeight + 24)
        }
        .scrollIndicators(.hidden)
        .background(CoveInkBackground())
        .navigationTitle("On-device models")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    // MARK: - Embedding encoders

    private var embeddingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                "Embedding model",
                systemImage: "cube.transparent",
                status: embeddingStatus
            )

            specs

            if let embeddingError {
                note(embeddingError, tint: .red)
            } else if embedding?.isBundled == false {
                note(
                    "The encoders are missing from this build. They are part of the app, not a download — reinstalling Cove is the only fix.",
                    tint: .red
                )
            } else {
                note(
                    "MobileCLIP2-S0 ships inside the app, so there is nothing to fetch. Reloading re-reads both encoders from the bundle.",
                    tint: nil
                )
            }

            HStack(spacing: 10) {
                Button {
                    Task { await prepare(reloading: embedding?.isLoaded == true) }
                } label: {
                    Label(
                        embedding?.isLoaded == true ? "Reload" : "Load now",
                        systemImage: isPreparing ? "hourglass" : "arrow.clockwise"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .tint(CoveTheme.ink)
                .disabled(isPreparing || embedding?.isBundled == false)

                Spacer(minLength: 0)
            }

            Divider().overlay(CoveTheme.hairline)

            reindexRow
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var specs: some View {
        VStack(alignment: .leading, spacing: 6) {
            spec("Version", embedding?.version ?? MobileCLIPEmbeddingService.modelVersion)
            spec(
                "Dimension",
                embedding?.dimension.map { "\($0)-d" }
                    // Read off the compiled model, so it genuinely is unknown
                    // until something has loaded it.
                    ?? "read on load"
            )
            spec("Input", embedding?.inputSize.map { "\($0)×\($0)" } ?? "read on load")
            if let loadDuration {
                spec("Last load", loadDuration.formattedMilliseconds)
            }
        }
    }

    /// Re-embedding is the one action here that touches saved data, so it says
    /// what it will do to how much before it does it.
    private var reindexRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Re-index the shelf")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CoveTheme.ink)

            Text("Runs \(readyItemCount) finished item\(readyItemCount == 1 ? "" : "s") through both encoders again. Text and summaries are untouched; only the search vectors are rewritten.")
                .font(.caption)
                .foregroundStyle(CoveTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    Task { await reindex() }
                } label: {
                    Label("Re-index", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .tint(CoveTheme.ink)
                .disabled(isReindexing || readyItemCount == 0)

                if isReindexing {
                    ProgressView().controlSize(.small)
                } else if let reindexedCount {
                    Text("\(reindexedCount) queued")
                        .font(.caption)
                        .foregroundStyle(CoveTheme.inkSecondary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Language model

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                "Language model",
                systemImage: "sparkles",
                status: languageStatus
            )

            note(
                languageModel?.errorDescription
                    ?? "Apple Intelligence is on and the system model is ready. Summaries and extraction run through it.",
                tint: languageModel == nil ? nil : .orange
            )

            note(
                "This one belongs to iOS, not to Cove — the app can read whether it is ready, but only Settings can turn it on or start its download.",
                tint: nil
            )

            HStack(spacing: 10) {
                if languageModel != nil, languageModel != .deviceNotEligible {
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else {
                            return
                        }
                        UIApplication.shared.open(url)
                    } label: {
                        Label("Open Settings", systemImage: "gearshape")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .tint(CoveTheme.ink)
                }

                Button {
                    languageModel = FoundationModelsService.availabilityError()
                } label: {
                    Label("Check again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .tint(CoveTheme.ink)

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.subheadline)
                .foregroundStyle(CoveTheme.ink.opacity(0.7))

            Text("Neither model sends anything anywhere. Cove links no networking API at all — captures, embeddings, and search stay on this device.")
                .font(.footnote)
                .foregroundStyle(CoveTheme.ink.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    // MARK: - Status

    private struct Status {
        let label: String
        let tint: Color
    }

    private var embeddingStatus: Status {
        if embeddingError != nil { return Status(label: "Failed", tint: .red) }
        guard let embedding else { return Status(label: "Checking", tint: .orange) }
        if !embedding.isBundled { return Status(label: "Missing", tint: .red) }
        return embedding.isLoaded
            ? Status(label: "Ready", tint: .green)
            : Status(label: "Not loaded", tint: .orange)
    }

    private var languageStatus: Status {
        switch languageModel {
        case nil: Status(label: "Ready", tint: .green)
        case .modelNotReady: Status(label: "Downloading", tint: .orange)
        case .appleIntelligenceNotEnabled: Status(label: "Turned off", tint: .orange)
        case .deviceNotEligible: Status(label: "Unsupported", tint: .red)
        case .other: Status(label: "Unavailable", tint: .red)
        }
    }

    // MARK: - Pieces

    private func cardHeader(_ title: String, systemImage: String, status: Status) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
                .foregroundStyle(CoveTheme.ink.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(CoveTheme.ink.opacity(0.08), in: Circle())

            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Circle()
                    .fill(status.tint)
                    .frame(width: 7, height: 7)
                Text(status.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CoveTheme.ink.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(CoveTheme.ink.opacity(0.07), in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(status.label)")
    }

    private func spec(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(CoveTheme.inkSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(CoveTheme.ink)
        }
    }

    @ViewBuilder
    private func note(_ text: String, tint: Color?) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(tint ?? CoveTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func refresh() async {
        languageModel = FoundationModelsService.availabilityError()
        embedding = await MobileCLIPEmbeddingService.shared.readiness
    }

    private func prepare(reloading: Bool) async {
        isPreparing = true
        embeddingError = nil
        defer { isPreparing = false }

        let service = MobileCLIPEmbeddingService.shared
        if reloading { await service.unload() }

        let start = ContinuousClock.now
        do {
            embedding = try await service.prepare()
            loadDuration = ContinuousClock.now - start
        } catch {
            embeddingError = error.localizedDescription
            embedding = await service.readiness
            loadDuration = nil
        }
    }

    private func reindex() async {
        isReindexing = true
        defer { isReindexing = false }
        reindexedCount = await ShelfProcessor.shared.reindexEmbeddings()
    }
}

private extension Duration {
    /// Load times land between tens and hundreds of milliseconds, which is the
    /// only range worth reporting here.
    var formattedMilliseconds: String {
        let milliseconds = Double(components.seconds) * 1000
            + Double(components.attoseconds) / 1e15
        return String(format: "%.0f ms", milliseconds)
    }
}

#Preview("Models") {
    NavigationStack {
        ModelSetupView()
            .modelContainer(for: [ShelfItem.self, ChatThread.self], inMemory: true)
    }
}
