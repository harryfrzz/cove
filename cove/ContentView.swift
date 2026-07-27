//
//  ContentView.swift
//  cove
//
//  Created by Harikrishna C on 22/07/26.
//

import SwiftData
import SwiftUI

/// App shell: owns the root tab selection, the capture surfaces reachable from
/// the bottom bar, and the app-wide background work that must keep running no
/// matter which tab is on screen.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]

    @AppStorage(CoveAppearance.storageKey) private var appearance = CoveAppearance.system

    @State private var tab: CoveTab = .home
    @State private var addMode: AddCaptureMode?
    @State private var isShowingCamera = false
    @State private var quickCapture = QuickCaptureCoordinator.shared
    @State private var categorizer = ShelfCategorizer.shared
    @State private var importer = GalleryImporter.shared

    var body: some View {
        ZStack {
            CoveInkBackground()

            switch tab {
            case .home:
                NavigationStack {
                    HomeDashboardView(onOpenWallet: { tab = .wallet })
                }
            case .shelf:
                ShelfView { addMode = .photo }
            case .chat:
                NavigationStack { ChatView() }
            case .wallet:
                NavigationStack { WalletView() }
            case .profile:
                ProfileView(
                    onOpenShelf: { tab = .shelf },
                    onOpenWallet: { tab = .wallet }
                )
            }
        }
        // Follows the system unless the profile page says otherwise. Applied
        // at the shell so sheets and full-screen covers presented from here
        // inherit it too.
        .preferredColorScheme(appearance.colorScheme)
        .safeAreaInset(edge: .bottom) {
            CoveTabBar(
                selection: $tab,
                onCamera: { isShowingCamera = true },
                onAdd: { addMode = $0 }
            )
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
        .task {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--open-wallet") {
                tab = .wallet
            }
            if ProcessInfo.processInfo.arguments.contains("--open-shelf") {
                tab = .shelf
            }
            if ProcessInfo.processInfo.arguments.contains("--open-profile") {
                tab = .profile
            }
            if ProcessInfo.processInfo.arguments.contains("--open-chat") {
                tab = .chat
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

#Preview {
    ContentView()
        .modelContainer(for: ShelfItem.self, inMemory: true)
        .environment(\.aiServices, .mock)
}
