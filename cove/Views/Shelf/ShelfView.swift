import SwiftData
import SwiftUI

struct ShelfView: View {
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    @Environment(\.modelContext) private var modelContext
    @State private var addMode: AddCaptureMode?
    @State private var isShowingCamera = false
    @State private var quickCapture = QuickCaptureCoordinator.shared
    @State private var categorizer = ShelfCategorizer.shared
    @State private var importer = GalleryImporter.shared
    @State private var isShowingWallet = false

    var body: some View {
        NavigationStack {
            ZStack {
                CoveInkBackground()

                if items.isEmpty, !importer.isImporting {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        topBar
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 8)

                        ScrollView {
                            if importer.isImporting {
                                importProgressChip
                                    .padding(.top, 4)
                                    .padding(.bottom, 8)
                            }

                            CategoryStackGrid(
                                items: items,
                                groups: categorizer.group(items)
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.light)
            .safeAreaInset(edge: .bottom) {
                GlassEffectContainer(spacing: 14) {
                    HStack(spacing: 14) {
                        searchBar

                        Menu {
                            if CameraCaptureView.isAvailable {
                                Button {
                                    isShowingCamera = true
                                } label: {
                                    Label("Camera", systemImage: "camera")
                                }
                            }
                            ForEach(AddCaptureMode.allCases) { mode in
                                Button {
                                    addMode = mode
                                } label: {
                                    Label(mode.rawValue, systemImage: mode.systemImage)
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(CoveTheme.ink)
                        .controlSize(.large)
                        .accessibilityLabel("Add")
                        .accessibilityHint("Add a screenshot, link, or note")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
            }
            .sheet(item: $addMode) { mode in
                AddItemView(initialMode: mode) { didSubmit in
                    guard !didSubmit else { return }
                    Task {
                        await ProcessingLiveActivityManager.shared.quickCaptureClosed()
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraCaptureView { image in
                    saveCameraCapture(image)
                }
                .ignoresSafeArea()
            }
            .navigationDestination(isPresented: $isShowingWallet) {
                WalletView()
            }
            .task {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--open-wallet") {
                    isShowingWallet = true
                }
#endif
                await categorizer.prepareIfNeeded()
            }
            .task {
                // Auto-index the photo library (prompts for access on first
                // launch, dedupes by asset on every later launch).
                await importer.importLibrary()
            }
            .task(id: processingActivitySnapshot) {
                await ProcessingLiveActivityManager.shared.synchronize(with: items)
            }
            .onChange(of: quickCapture.requestID, initial: true) { _, requestID in
                guard let requestID else { return }
                addMode = .photo
                quickCapture.consume(requestID)
                Task {
                    await ProcessingLiveActivityManager.shared.quickCaptureStarted()
                }
            }
        }
    }

    private var importProgressChip: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Indexing your library · \(importer.importedCount)/\(importer.totalCount)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(CoveTheme.inkSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 8) {
            NavigationLink {
                WalletView()
            } label: {
                Image(systemName: "wallet.pass")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CoveTheme.ink.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular, in: Circle())
            }
            .accessibilityLabel("Wallet")

#if DEBUG
            NavigationLink {
                AIDiagnosticsView()
            } label: {
                Image(systemName: "stethoscope")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CoveTheme.ink.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular, in: Circle())
            }
            .accessibilityLabel("AI diagnostics")
#endif

            Spacer()

            Text("Cove")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)

            Spacer()

            Text("\(items.count)")
                .font(.system(.subheadline, design: .serif, weight: .bold))
                .foregroundStyle(.orange)
                .frame(minWidth: 36, minHeight: 36)
                .glassEffect(.regular, in: Circle())
                .accessibilityLabel("\(items.count) items")
        }
    }

    private var searchBar: some View {
        NavigationLink {
            ShelfSearchView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                Text("Search anything")
                Spacer()
            }
            .foregroundStyle(CoveTheme.ink.opacity(0.55))
            .padding(.horizontal, 18)
            .frame(height: 52)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CoveTheme.ink)

            VStack(spacing: 8) {
                Text("Your shelf is clear")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(CoveTheme.ink)
                Text("Drop in a screenshot, link, or thought.\nCove keeps it local and easy to find.")
                    .font(.subheadline)
                    .foregroundStyle(CoveTheme.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                addMode = .photo
            } label: {
                Label("Add your first item", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(CoveTheme.ink)
            .padding(.top, 6)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 30)
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .padding(36)
        .accessibilityElement(children: .combine)
    }

    /// Camera captures skip the add form: store a downscaled copy and hand
    /// it straight to the processing pipeline, like a library import.
    private func saveCameraCapture(_ image: UIImage) {
        let item = ShelfItem(
            kind: .image,
            title: "Camera · \(Date.now.formatted(date: .abbreviated, time: .omitted))",
            imageData: image.downscaledJPEGData(),
            processingState: .queued
        )
        modelContext.insert(item)
        try? modelContext.save()

        let itemID = item.id
        Task {
            await ShelfProcessor.shared.enqueue(itemID: itemID)
        }
    }

    private var processingActivitySnapshot: String {
        items.map {
            "\($0.id.uuidString):\($0.processingState.rawValue):\($0.title)"
        }
        .joined(separator: "|")
    }
}

#Preview("Empty shelf") {
    ShelfView()
        .modelContainer(for: ShelfItem.self, inMemory: true)
        .environment(\.aiServices, .mock)
}
