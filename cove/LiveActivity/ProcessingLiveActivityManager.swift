import ActivityKit
import Foundation

/// Value snapshot of a shelf item for Live Activity updates, so background
/// actors never hand SwiftData model objects across actor boundaries.
struct ShelfItemActivitySnapshot: Sendable {
    let id: UUID
    let title: String
    let kindLabel: String
    let createdAt: Date
}

extension ShelfItem {
    var activitySnapshot: ShelfItemActivitySnapshot {
        ShelfItemActivitySnapshot(
            id: id,
            title: title,
            kindLabel: kind.label,
            createdAt: createdAt
        )
    }
}

@MainActor
final class ProcessingLiveActivityManager {
    static let shared = ProcessingLiveActivityManager()

    private struct ProcessingItem {
        let title: String
        let kind: String
        let createdAt: Date
        var phase: CoveProcessingPhase
        var progress: Double
    }

    private var processingItems: [UUID: ProcessingItem] = [:]
    private var activity: Activity<CoveProcessingAttributes>?
    private var isQuickCaptureOpen = false
    private var terminalState: CoveProcessingAttributes.ContentState?
    private var dismissalTask: Task<Void, Never>?
    private var latestTitle = "Processing shelf item"
    private var latestKind = "Item"

    private init() {}

    func quickCaptureStarted() async {
        cancelPendingDismissal()
        isQuickCaptureOpen = true
        latestTitle = "Ready to capture"
        latestKind = "Quick Capture"
        await refreshActivity()
    }

    func quickCaptureClosed() async {
        isQuickCaptureOpen = false
        await refreshActivity()
    }

    func itemStarted(_ item: ShelfItemActivitySnapshot) async {
        cancelPendingDismissal()
        isQuickCaptureOpen = false
        latestTitle = item.title
        latestKind = item.kindLabel
        processingItems[item.id] = ProcessingItem(
            title: item.title,
            kind: item.kindLabel,
            createdAt: item.createdAt,
            phase: .preparing,
            progress: 0.1
        )
        await refreshActivity()
    }

    func itemProgress(
        id: UUID,
        phase: CoveProcessingPhase,
        progress: Double
    ) async {
        guard var processingItem = processingItems[id] else { return }
        processingItem.phase = phase
        processingItem.progress = min(max(progress, 0), 1)
        processingItems[id] = processingItem
        latestTitle = processingItem.title
        latestKind = processingItem.kind
        await refreshActivity()
    }

    func itemFinished(_ item: ShelfItemActivitySnapshot) async {
        processingItems[item.id] = nil
        guard processingItems.isEmpty else {
            updateLatestProcessingItem()
            await refreshActivity()
            return
        }

        terminalState = CoveProcessingAttributes.ContentState(
            processingCount: 0,
            latestTitle: item.title,
            latestKind: item.kindLabel,
            phase: .ready,
            progress: 1
        )
        await refreshActivity()
        scheduleDismissal(after: .seconds(2))
    }

    func itemFailed(_ item: ShelfItemActivitySnapshot) async {
        processingItems[item.id] = nil
        guard processingItems.isEmpty else {
            updateLatestProcessingItem()
            await refreshActivity()
            return
        }

        terminalState = CoveProcessingAttributes.ContentState(
            processingCount: 0,
            latestTitle: item.title,
            latestKind: item.kindLabel,
            phase: .failed,
            progress: 1
        )
        await refreshActivity()
        scheduleDismissal(after: .seconds(4))
    }

    func synchronize(with items: [ShelfItem]) async {
        guard processingItems.isEmpty,
              terminalState == nil,
              !isQuickCaptureOpen else {
            return
        }

        processingItems = Dictionary(
            uniqueKeysWithValues: items
                .filter { $0.processingState == .processing || $0.processingState == .queued }
                .map {
                    (
                        $0.id,
                        ProcessingItem(
                            title: $0.title,
                            kind: $0.kind.label,
                            createdAt: $0.createdAt,
                            phase: .preparing,
                            progress: 0.1
                        )
                    )
                }
        )

        if let newest = processingItems.values.max(by: { $0.createdAt < $1.createdAt }) {
            latestTitle = newest.title
            latestKind = newest.kind
        }
        await refreshActivity()
    }

    private func refreshActivity() async {
        let shouldShowActivity = isQuickCaptureOpen || !processingItems.isEmpty || terminalState != nil
        let state = currentContentState()
        let content = ActivityContent(
            state: state,
            staleDate: shouldShowActivity ? .now.addingTimeInterval(5 * 60) : nil
        )

        if !shouldShowActivity {
            guard let currentActivity = activity ?? Activity<CoveProcessingAttributes>.activities.first else {
                return
            }
            await currentActivity.end(content, dismissalPolicy: .immediate)
            activity = nil
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let currentActivity = activity ?? Activity<CoveProcessingAttributes>.activities.first {
            activity = currentActivity
            await currentActivity.update(content)
            return
        }

        do {
            activity = try Activity.request(
                attributes: CoveProcessingAttributes(sessionID: UUID()),
                content: content,
                pushType: nil
            )
        } catch {
            // Live Activities are a glance surface; processing must continue if unavailable.
        }
    }

    private func currentContentState() -> CoveProcessingAttributes.ContentState {
        if let terminalState {
            return terminalState
        }

        if let newest = processingItems.values.max(by: { $0.createdAt < $1.createdAt }) {
            return CoveProcessingAttributes.ContentState(
                processingCount: processingItems.count,
                latestTitle: newest.title,
                latestKind: newest.kind,
                phase: newest.phase,
                progress: newest.progress
            )
        }

        return CoveProcessingAttributes.ContentState(
            processingCount: 0,
            latestTitle: latestTitle,
            latestKind: latestKind,
            phase: isQuickCaptureOpen ? .readyToCapture : .ready,
            progress: isQuickCaptureOpen ? 0 : 1
        )
    }

    private func updateLatestProcessingItem() {
        guard let newest = processingItems.values.max(by: { $0.createdAt < $1.createdAt }) else {
            return
        }
        latestTitle = newest.title
        latestKind = newest.kind
    }

    private func cancelPendingDismissal() {
        dismissalTask?.cancel()
        dismissalTask = nil
        terminalState = nil
    }

    private func scheduleDismissal(after duration: Duration) {
        dismissalTask?.cancel()
        dismissalTask = Task { @MainActor in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }

            terminalState = nil
            dismissalTask = nil
            await refreshActivity()
        }
    }
}
