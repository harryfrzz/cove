import AppIntents
import Foundation
import Observation
import SwiftData
import UIKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class QuickCaptureCoordinator {
    static let shared = QuickCaptureCoordinator()

    private(set) var requestID: UUID?

    private init() {}

    func requestQuickCapture() {
        requestID = UUID()
    }

    func consume(_ requestID: UUID) {
        guard self.requestID == requestID else { return }
        self.requestID = nil
    }
}

struct CoveQuickCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Capture in Cove"
    static let description = IntentDescription(
        "Opens Cove's local capture sheet and shows its status in the Dynamic Island."
    )
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCaptureCoordinator.shared.requestQuickCapture()
        return .result()
    }
}

struct ProcessScreenshotIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Process Screenshot in Cove"
    static let description = IntentDescription(
        "Saves an image to Cove, processes it locally, and shows progress as a Live Activity."
    )
    static var supportedModes: IntentModes { .background }

    @Parameter(
        title: "Screenshot",
        description: "The screenshot to save and process locally.",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let imageData = screenshot.data
        guard !imageData.isEmpty, UIImage(data: imageData) != nil else {
            throw ProcessScreenshotError.invalidImage
        }

        let modelContext = ModelContext(CoveStore.shared)
        let item = ShelfItem(
            kind: .screenshot,
            title: "Screenshot at \(Date.now.formatted(date: .omitted, time: .shortened))",
            imageData: imageData,
            processingState: .queued
        )
        modelContext.insert(item)

        do {
            try modelContext.save()
        } catch {
            throw ProcessScreenshotError.couldNotSave
        }

        let finalState = await ShelfProcessor.shared.processNow(itemID: item.id)
        guard finalState == .ready else {
            throw ProcessScreenshotError.processingFailed
        }
        return .result(dialog: "Screenshot saved to Cove.")
    }
}

private enum ProcessScreenshotError: LocalizedError {
    case invalidImage
    case couldNotSave
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "Cove needs an image from the previous Shortcut action."
        case .couldNotSave:
            "Cove couldn’t save this screenshot locally."
        case .processingFailed:
            "Cove saved the screenshot but couldn’t finish processing it."
        }
    }
}

struct CoveAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CoveQuickCaptureIntent(),
            phrases: [
                "Quick capture with \(.applicationName)",
                "Add something to \(.applicationName)"
            ],
            shortTitle: "Quick Capture",
            systemImageName: "square.and.pencil"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .navy }
}
