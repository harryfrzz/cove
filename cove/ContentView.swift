//
//  ContentView.swift
//  cove
//
//  Created by Harikrishna C on 22/07/26.
//

import FoundationModels
import SwiftData
import SwiftUI

/// App shell: owns the root tab selection, the capture surfaces reachable from
/// the bottom bar, and the app-wide background work that must keep running no
/// matter which tab is on screen.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    /// Newest first, so dock prompts land in the conversation the chat screen
    /// would resume rather than starting a thread each time.
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]

    @AppStorage(CoveAppearance.storageKey) private var appearance = CoveAppearance.system

    @State private var tab: CoveTab = .home
    @State private var addMode: AddCaptureMode?
    @State private var isShowingCamera = false
    @State private var quickCapture = QuickCaptureCoordinator.shared
    @State private var categorizer = ShelfCategorizer.shared
    @State private var importer = GalleryImporter.shared
    @State private var aiSession: LanguageModelSession?

    /// Temporary stand-in while the dock's prompt card is being tuned: every
    /// prompt takes three seconds and answers "meow", so the shimmer has
    /// something predictable to play against. Set to `false` to go back to the
    /// on-device model below, which is otherwise untouched.
    private static let usesDummyAIReply = true

    var body: some View {
        ZStack {
            CoveInkBackground()

            switch tab {
            case .home:
                ShelfView { addMode = .photo }
            case .wallet:
                NavigationStack { HomeDashboardView() }
            case .upcoming:
                NavigationStack { UpcomingView() }
            case .profile:
                ProfileView()
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
                onAdd: { addMode = $0 },
                onAIPrompt: submitAIPrompt
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
                tab = .home
            }
            if ProcessInfo.processInfo.arguments.contains("--open-profile") {
                tab = .profile
            }
            if ProcessInfo.processInfo.arguments.contains("--open-upcoming") {
                tab = .upcoming
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

    /// Answers the dock's one-shot prompt without navigating to a separate
    /// chat screen. The model stays on-device and receives a compact snapshot
    /// of the user's shelf as context.
    ///
    /// Both sides of the exchange are written to the newest `ChatThread` on the
    /// way past. The dock's card is discarded when it collapses, and `aiSession`
    /// outlives it — without this the model would keep context the user had no
    /// way to see again.
    private func submitAIPrompt(_ text: String) async -> String {
        if Self.usesDummyAIReply {
            try? await Task.sleep(for: .seconds(3))
            let answer = "meow"
            record(question: text, answer: answer)
            return answer
        }

        if let unavailable = FoundationModelsService.availabilityError() {
            return unavailable.errorDescription ?? "The on-device model is unavailable."
        }

        let active = aiSession ?? LanguageModelSession(instructions: aiInstructions)
        aiSession = active

        let answer: String
        do {
            let response = try await active.respond(to: text)
            let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            answer = content.isEmpty ? "I couldn't find an answer for that." : content
        } catch {
            answer = "That didn't go through — \(error.localizedDescription)"
        }

        record(question: text, answer: answer)
        return answer
    }

    /// Appends the exchange to the conversation the chat screen will resume,
    /// starting one if there is none yet.
    private func record(question: String, answer: String) {
        let thread: ChatThread
        if let existing = threads.first {
            thread = existing
        } else {
            thread = ChatThread()
            modelContext.insert(thread)
        }

        modelContext.insert(thread.append(role: .user, text: question))
        modelContext.insert(thread.append(role: .assistant, text: answer))
        try? modelContext.save()
    }

    private var aiInstructions: String {
        """
        You are Cove, an assistant for a personal shelf of saved screenshots, \
        tickets, receipts, links, and notes. Answer in one or two short \
        sentences. Use the saved items below when relevant, and say you cannot \
        find something rather than inventing details.

        Saved items:
        \(aiShelfDigest)
        """
    }

    private var aiShelfDigest: String {
        let lines = items
            .filter { $0.processingState == .ready }
            .prefix(12)
            .map { item -> String in
                let detail = item.summary
                    ?? item.extraction?.shortTitle
                    ?? item.kind.label
                return "- \(item.title): \(detail)"
            }
        return lines.isEmpty ? "(nothing saved yet)" : lines.joined(separator: "\n")
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
        .modelContainer(for: [ShelfItem.self, ChatThread.self], inMemory: true)
        .environment(\.aiServices, .mock)
}
